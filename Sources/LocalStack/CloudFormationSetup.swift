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

    private let logger: Logger

    public init(
        templatePath: String,
        stackName: String = "test-stack",
        parameters: [String: String] = [:],
        logger: Logger = Logger(label: "CloudFormationSetup")
    ) {
        self.templatePath = templatePath
        self.stackName = stackName
        self.parameters = parameters
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

        // 2. If the template was synthesized by CDK, it references the
        //    `/cdk-bootstrap/hnb659fds/version` SSM parameter. Stub it in
        //    LocalStack before CreateStack so the default value resolves
        //    and the CheckBootstrapVersion rule passes.
        if BootstrapVersionStub.templateNeedsStub(templateBody) {
            try await BootstrapVersionStub.stub(endpoint: endpoint, logger: logger)
        }

        // 3. Create stack via LocalStack CloudFormation HTTP API
        try await createStack(endpoint: endpoint, templateBody: templateBody)

        // 4. Wait for stack creation to complete
        try await waitForStack(endpoint: endpoint)
    }

    public func tearDown(container: RunningContainer) async throws {
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()
        logger.info("Deleting CF stack", metadata: ["stack": "\(stackName)"])

        // DELETE stack — best effort; container teardown will clean up regardless
        _ = try? await deleteStack(endpoint: endpoint)
    }

    // MARK: - Stack Outputs

    /// Extracts output key-value pairs from a DescribeStacks XML response.
    ///
    /// Parses `<Outputs><member><OutputKey>…</OutputKey><OutputValue>…</OutputValue></member>…</Outputs>`.
    internal func extractOutputs(from xml: String) -> [String: String] {
        var outputs: [String: String] = [:]

        guard let openRange = xml.range(of: "<Outputs>"),
            let closeRange = xml.range(of: "</Outputs>", range: openRange.upperBound..<xml.endIndex)
        else {
            return outputs
        }

        let section = String(xml[openRange.upperBound..<closeRange.lowerBound])
        var searchStart = section.startIndex

        while let memberOpen = section.range(of: "<member>", range: searchStart..<section.endIndex),
            let memberClose = section.range(of: "</member>", range: memberOpen.upperBound..<section.endIndex)
        {
            let member = String(section[memberOpen.upperBound..<memberClose.lowerBound])

            if let key = extractTag("OutputKey", from: member),
                let value = extractTag("OutputValue", from: member)
            {
                outputs[key] = value
            }

            searchStart = memberClose.upperBound
        }

        return outputs
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

    // MARK: - Private

    private func createStack(endpoint: String, templateBody: String) async throws {
        var fields: [(String, String)] = [
            ("Action", "CreateStack"),
            ("StackName", stackName),
            ("TemplateBody", templateBody),
        ]

        for (index, parameter) in parameters.sorted(by: { $0.key < $1.key }).enumerated() {
            let position = index + 1
            fields.append(("Parameters.member.\(position).ParameterKey", parameter.key))
            fields.append(("Parameters.member.\(position).ParameterValue", parameter.value))
        }

        try await executeCloudFormation(endpoint: endpoint, fields: fields)
    }

    private func waitForStack(endpoint: String) async throws {
        let deadline = ContinuousClock.now + .seconds(120)

        while ContinuousClock.now < deadline {
            let xml = try await describeStack(endpoint: endpoint)

            if let status = extractTag("StackStatus", from: xml) {
                switch status {
                case "CREATE_COMPLETE":
                    return
                case _
                where status.hasPrefix("CREATE_FAILED")
                    || status.hasPrefix("ROLLBACK")
                    || status.hasPrefix("DELETE"):
                    let reason = extractTag("StackStatusReason", from: xml) ?? status
                    throw ContainerError.setupFailed(
                        step: "CloudFormationSetup",
                        reason: "Stack entered terminal state \(status): \(reason)"
                    )
                default:
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(500))
        }

        throw ContainerError.setupFailed(
            step: "CloudFormationSetup",
            reason: "Timed out waiting for stack \(stackName) to reach CREATE_COMPLETE"
        )
    }

    private func deleteStack(endpoint: String) async throws {
        let fields: [(String, String)] = [
            ("Action", "DeleteStack"),
            ("StackName", stackName),
        ]
        try await executeCloudFormation(endpoint: endpoint, fields: fields)
    }

    private func describeStack(endpoint: String) async throws -> String {
        let fields: [(String, String)] = [
            ("Action", "DescribeStacks"),
            ("StackName", stackName),
        ]
        return try await executeCloudFormation(endpoint: endpoint, fields: fields)
    }

    // MARK: - HTTP Helpers

    @discardableResult
    private func executeCloudFormation(
        endpoint: String,
        fields: [(String, String)]
    ) async throws -> String {
        var request = HTTPClientRequest(url: endpoint)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .bytes(Data(formEncodedBody(fields).utf8))

        let response = try await HTTPClient.shared.execute(
            request,
            timeout: .seconds(30)
        )
        let body = try await response.body.collect(upTo: 1024 * 1024)
        let xml = String(buffer: body)

        guard (200..<300).contains(response.status.code) else {
            throw ContainerError.setupFailed(
                step: "CloudFormationSetup",
                reason: "HTTP \(response.status.code): \(xml)"
            )
        }

        return xml
    }

    private func formEncodedBody(_ fields: [(String, String)]) -> String {
        fields.map { key, value in
            let encodedKey =
                key.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryValueAllowed
                ) ?? key
            let encodedValue =
                value.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryValueAllowed
                ) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}

// MARK: - OutputProducingSetup

extension CloudFormationSetup: OutputProducingSetup {
    public func fetchOutputs(
        from container: RunningContainer
    ) async throws -> [String: String] {
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()
        var outputs = extractOutputs(from: try await describeStack(endpoint: endpoint))
        outputs["_awsEndpoint"] = endpoint
        return outputs
    }
}

// MARK: - URL Encoding

extension CharacterSet {
    fileprivate static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=&#")
        return allowed
    }()
}
