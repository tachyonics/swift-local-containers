import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging

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
        logger.info("Deploying CF stack", metadata: [
            "stack": "\(stackName)",
            "endpoint": "\(endpoint)",
            "template": "\(templatePath)",
        ])

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

    // MARK: - Private

    private func createStack(endpoint: String, templateBody: String) async throws {
        // TODO: POST to <endpoint>/ with Action=CreateStack
        // Query parameters: StackName, TemplateBody, Parameters
        throw ContainerError.setupFailed(
            step: "CloudFormationSetup",
            reason: "createStack not yet implemented"
        )
    }

    private func waitForStack(endpoint: String) async throws {
        // TODO: Poll DescribeStacks until status is CREATE_COMPLETE
        throw ContainerError.setupFailed(
            step: "CloudFormationSetup",
            reason: "waitForStack not yet implemented"
        )
    }

    private func deleteStack(endpoint: String) async throws {
        // TODO: POST to <endpoint>/ with Action=DeleteStack
        throw ContainerError.setupFailed(
            step: "CloudFormationSetup",
            reason: "deleteStack not yet implemented"
        )
    }
}
