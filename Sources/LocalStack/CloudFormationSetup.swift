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
                "template": "\(templatePath)"
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
            "TemplateBody=\(formEncode(templateBody))"
        ]

        for (index, key) in parameters.keys.sorted().enumerated() {
            let memberIndex = index + 1
            parts.append(
                "Parameters.member.\(memberIndex).ParameterKey=\(formEncode(key))"
            )
            parts.append(
                "Parameters.member.\(memberIndex).ParameterValue=\(formEncode(parameters[key]!))"
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

    // MARK: - Stack Outputs

    /// Fetches the outputs of the deployed stack from CloudFormation.
    ///
    /// Calls `DescribeStacks` and parses the `<Outputs>` section.
    /// Should be called after the stack reaches `CREATE_COMPLETE`.
    public func fetchOutputs(endpoint: String) async throws -> [String: String] {
        let body = "Action=\(formEncode("DescribeStacks"))&StackName=\(formEncode(stackName))"

        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(ByteBuffer(string: body))

        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))
        let responseBody = try await response.body.collect(upTo: Self.maxResponseSize)
        let xml = String(buffer: responseBody)

        return Self.extractOutputs(from: xml)
    }

    /// Extracts output key-value pairs from a DescribeStacks XML response.
    ///
    /// Parses `<Outputs><member><OutputKey>...</OutputKey><OutputValue>...</OutputValue></member>...</Outputs>`.
    internal static func extractOutputs(from xml: String) -> [String: String] {
        var outputs: [String: String] = [:]

        // Find the <Outputs>...</Outputs> section
        let outputsOpen = "<Outputs>"
        let outputsClose = "</Outputs>"
        guard let openRange = xml.range(of: outputsOpen),
            let closeRange = xml.range(of: outputsClose, range: openRange.upperBound..<xml.endIndex)
        else {
            return outputs
        }

        let outputsSection = String(xml[openRange.upperBound..<closeRange.lowerBound])

        // Parse each <member> block
        var searchStart = outputsSection.startIndex
        while let memberOpen = outputsSection.range(of: "<member>", range: searchStart..<outputsSection.endIndex),
            let memberClose = outputsSection.range(
                of: "</member>",
                range: memberOpen.upperBound..<outputsSection.endIndex
            )
        {
            let member = String(outputsSection[memberOpen.upperBound..<memberClose.lowerBound])

            if let key = extractTag("OutputKey", from: member),
                let value = extractTag("OutputValue", from: member)
            {
                outputs[key] = value
            }

            searchStart = memberClose.upperBound
        }

        return outputs
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

extension CharacterSet {
    fileprivate static let cloudFormationFormAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return allowed
    }()
}

private func formEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .cloudFormationFormAllowed) ?? value
}

private func extractTag(_ tag: String, from xml: String) -> String? {
    let open = "<\(tag)>"
    let close = "</\(tag)>"
    guard let openRange = xml.range(of: open),
        let closeRange = xml.range(of: close, range: openRange.upperBound..<xml.endIndex)
    else {
        return nil
    }
    let value = String(xml[openRange.upperBound..<closeRange.lowerBound])
    return value.isEmpty ? nil : value
}
