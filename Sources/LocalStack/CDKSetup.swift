import Foundation
import LocalContainers
import Logging

/// A ``ContainerSetup`` that runs `cdk bootstrap`, `cdk synth`, and deploys
/// the resulting template to a LocalStack container.
///
/// Use this when the CDK code is the source of truth and you want tests to
/// always use the latest infrastructure definition.
public struct CDKSetup: ContainerSetup {
    /// Directory containing the CDK app.
    public let cdkAppPath: String

    /// CDK stack to synthesize.
    public let stackName: String

    /// Command to invoke the CDK CLI (e.g. `"npx cdk"` or `"cdk"`).
    public let cdkCommand: String

    /// CloudFormation parameters to pass during deployment.
    public let parameters: [String: String]

    /// Whether to run `cdk bootstrap` before deploying.
    public let autoBootstrap: Bool

    private let logger: Logger

    public init(
        cdkAppPath: String,
        stackName: String,
        cdkCommand: String = "npx cdk",
        parameters: [String: String] = [:],
        autoBootstrap: Bool = true,
        logger: Logger = Logger(label: "CDKSetup")
    ) {
        self.cdkAppPath = cdkAppPath
        self.stackName = stackName
        self.cdkCommand = cdkCommand
        self.parameters = parameters
        self.autoBootstrap = autoBootstrap
        self.logger = logger
    }

    public func setUp(container: RunningContainer) async throws {
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()
        logger.info("CDK setup starting", metadata: [
            "stack": "\(stackName)",
            "endpoint": "\(endpoint)",
            "cdkApp": "\(cdkAppPath)",
        ])

        // 1. Bootstrap (if enabled)
        if autoBootstrap {
            try await bootstrap(endpoint: endpoint)
        }

        // 2. Synth
        let templatePath = try await synth()

        // 3. Deploy template via CloudFormation API
        let cfSetup = CloudFormationSetup(
            templatePath: templatePath,
            stackName: stackName,
            parameters: parameters,
            logger: logger
        )
        try await cfSetup.setUp(container: container)
    }

    public func tearDown(container: RunningContainer) async throws {
        let cfSetup = CloudFormationSetup(
            templatePath: "",
            stackName: stackName,
            logger: logger
        )
        try await cfSetup.tearDown(container: container)
    }

    // MARK: - Private

    private func bootstrap(endpoint: String) async throws {
        logger.info("Running cdk bootstrap")
        let args = "\(cdkCommand) bootstrap --app \(cdkAppPath) aws://000000000000/us-east-1"
        try await runShell(args, environment: ["AWS_ENDPOINT_URL": endpoint])
    }

    private func synth() async throws -> String {
        logger.info("Running cdk synth")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdk-synth-\(UUID().uuidString)")
            .path
        let args = "\(cdkCommand) synth --app \(cdkAppPath) --output \(tempDir) \(stackName)"
        try await runShell(args)

        let templatePath = "\(tempDir)/\(stackName).template.json"
        guard FileManager.default.fileExists(atPath: templatePath) else {
            throw ContainerError.setupFailed(
                step: "CDKSetup",
                reason: "Synthesized template not found at \(templatePath)"
            )
        }
        return templatePath
    }

    @discardableResult
    private func runShell(
        _ command: String,
        environment: [String: String] = [:]
    ) async throws -> String {
        // TODO: Use Foundation.Process to run the command
        throw ContainerError.setupFailed(
            step: "CDKSetup",
            reason: "Shell execution not yet implemented"
        )
    }
}
