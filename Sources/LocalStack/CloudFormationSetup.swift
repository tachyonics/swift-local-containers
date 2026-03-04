import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging
import NIOCore

/// A ``ContainerSetup`` that deploys a pre-synthesized CloudFormation template
/// to a LocalStack container.
public struct CloudFormationSetup: ContainerSetup {
    /// Path to the pre-synthesized CloudFormation template (JSON or YAML).
    public let templatePath: String

    /// CloudFormation stack name.
    public let stackName: String

    /// CloudFormation parameters.
    public let parameters: [String: String]

    /// Maximum time to wait for stack creation to complete.
    public let timeout: Duration

    /// Interval between DescribeStacks polls.
    public let pollInterval: Duration

    private let logger: Logger

    private static let maxResponseSize = 1_024 * 1_024

    public init(
        templatePath: String,
        stackName: String = "test-stack",
        parameters: [String: String] = [:],
        timeout: Duration = .seconds(120),
        pollInterval: Duration = .seconds(2),
        logger: Logger = Logger(label: "CloudFormationSetup")
    ) {
        self.templatePath = templatePath
        self.stackName = stackName
        self.parameters = parameters
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.logger = logger
    }

    public func setUp(container: RunningContainer) async throws {
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()
        logger.info(
            "Deploying CF stack",
            metadata: [
                "stack": "\(stackName)",
                "endpoint": "\(endpoint)",
                "template": "\(templatePath)",
            ]
        )

        // 1. Read template
        let templateURL = URL(fileURLWithPath: templatePath)
        let templateBody = try String(contentsOf: templateURL, encoding: .utf8)

        // 2. Create stack via LocalStack CloudFormation HTTP API
        try await createStack(endpoint: endpoint, templateBody: templateBody)

        // 3. Wait for stack creation to complete
        try await waitForStack(endpoint: endpoint)
    }

    public func tearDown(container: RunningContainer) async throws {
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()
        logger.info("Deleting CF stack", metadata: ["stack": "\(stackName)"])

        // DELETE stack — best effort; container teardown will clean up regardless
        _ = try? await deleteStack(endpoint: endpoint)
    }

    // MARK: - Internal (visible for testing)

    /// Builds the form-encoded body for a CreateStack request.
    internal func buildCreateStackBody(templateBody: String) -> String {
        var parts = [
            "Action=\(formEncode("CreateStack"))",
            "StackName=\(formEncode(stackName))",
            "TemplateBody=\(formEncode(templateBody))",
        ]

        for (index, key) in parameters.keys.sorted().enumerated() {
            let n = index + 1
            parts.append(
                "Parameters.member.\(n).ParameterKey=\(formEncode(key))"
            )
            parts.append(
                "Parameters.member.\(n).ParameterValue=\(formEncode(parameters[key]!))"
            )
        }

        return parts.joined(separator: "&")
    }

    /// Extracts the `<StackStatus>` value from a DescribeStacks XML response.
    internal static func extractStackStatus(from xml: String) -> String {
        let openTag = "<StackStatus>"
        let closeTag = "</StackStatus>"

        guard let openRange = xml.range(of: openTag),
            let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex)
        else {
            return "UNKNOWN"
        }

        let status = String(xml[openRange.upperBound..<closeRange.lowerBound])
        return status.isEmpty ? "UNKNOWN" : status
    }

    // MARK: - Private

    private func createStack(endpoint: String, templateBody: String) async throws {
        let body = buildCreateStackBody(templateBody: templateBody)

        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: body))

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))

        guard (200..<300).contains(Int(response.status.code)) else {
            let responseBody = try await response.body.collect(upTo: Self.maxResponseSize)
            let message = String(buffer: responseBody)
            throw ContainerError.setupFailed(
                step: "CloudFormationSetup",
                reason: "CreateStack failed: HTTP \(response.status.code) — \(message)"
            )
        }
    }

    private func waitForStack(endpoint: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ContainerError.setupFailed(
                    step: "CloudFormationSetup",
                    reason:
                        "Stack '\(stackName)' did not reach CREATE_COMPLETE within \(timeout)"
                )
            }

            group.addTask {
                while !Task.isCancelled {
                    let status = try await describeStackStatus(endpoint: endpoint)
                    logger.info(
                        "Stack status",
                        metadata: ["stack": "\(stackName)", "status": "\(status)"]
                    )

                    switch status {
                    case "CREATE_COMPLETE":
                        return
                    case "CREATE_IN_PROGRESS":
                        try await Task.sleep(for: pollInterval)
                    default:
                        throw ContainerError.setupFailed(
                            step: "CloudFormationSetup",
                            reason: "Stack '\(stackName)' entered status: \(status)"
                        )
                    }
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    private func describeStackStatus(endpoint: String) async throws -> String {
        let body = "Action=\(formEncode("DescribeStacks"))&StackName=\(formEncode(stackName))"

        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: body))

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))
        let responseBody = try await response.body.collect(upTo: Self.maxResponseSize)
        let xml = String(buffer: responseBody)

        return Self.extractStackStatus(from: xml)
    }

    private func deleteStack(endpoint: String) async throws {
        let body = "Action=\(formEncode("DeleteStack"))&StackName=\(formEncode(stackName))"

        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: body))

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))

        guard (200..<300).contains(Int(response.status.code)) else {
            let responseBody = try await response.body.collect(upTo: Self.maxResponseSize)
            let message = String(buffer: responseBody)
            throw ContainerError.setupFailed(
                step: "CloudFormationSetup",
                reason: "DeleteStack failed: HTTP \(response.status.code) — \(message)"
            )
        }
    }
}

// MARK: - Form Encoding

private extension CharacterSet {
    static let cloudFormationFormAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-_.~")
        return cs
    }()
}

private func formEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .cloudFormationFormAllowed) ?? value
}
