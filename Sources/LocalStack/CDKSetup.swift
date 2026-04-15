import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging
import NIOCore

/// A ``ContainerSetup`` that runs `cdk bootstrap`, `cdk synth`, and deploys
/// the resulting template to a LocalStack container.
///
/// Use this when the CDK code is the source of truth and you want tests to
/// always use the latest infrastructure definition.
public struct CDKSetup: ContainerSetup {
    /// Directory containing the CDK app (must contain `cdk.json`).
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
        logger.info(
            "CDK setup starting",
            metadata: [
                "stack": "\(stackName)",
                "endpoint": "\(endpoint)",
                "cdkApp": "\(cdkAppPath)",
            ]
        )

        if autoBootstrap {
            try await bootstrap(endpoint: endpoint)
        }
        // When autoBootstrap is false, we rely on CloudFormationSetup's
        // automatic template inspection to detect the CDK bootstrap
        // marker and stub the SSM parameter before CreateStack runs.
        // See ``BootstrapVersionStub`` for the rationale.

        let templatePath = try await synth(endpoint: endpoint)

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

    // MARK: - CDK CLI Invocations

    private func bootstrap(endpoint: String) async throws {
        logger.info("Running cdk bootstrap")
        let arguments =
            splitCommand(cdkCommand)
            + ["bootstrap", "aws://000000000000/us-east-1"]
        try await runShell(
            arguments,
            environment: cdkEnvironment(endpoint: endpoint)
        )
    }

    private func synth(endpoint: String) async throws -> String {
        logger.info("Running cdk synth")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdk-synth-\(UUID().uuidString)")
            .path
        let arguments =
            splitCommand(cdkCommand)
            + ["synth", "--output", tempDir, stackName]
        try await runShell(
            arguments,
            environment: cdkEnvironment(endpoint: endpoint)
        )

        let templatePath = "\(tempDir)/\(stackName).template.json"
        guard FileManager.default.fileExists(atPath: templatePath) else {
            throw ContainerError.setupFailed(
                step: "CDKSetup",
                reason: "Synthesized template not found at \(templatePath)"
            )
        }
        return templatePath
    }

    private func cdkEnvironment(endpoint: String) -> [String: String] {
        [
            "AWS_ENDPOINT_URL": endpoint,
            "CDK_DEFAULT_ACCOUNT": "000000000000",
            "CDK_DEFAULT_REGION": "us-east-1",
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
            "AWS_REGION": "us-east-1",
        ]
    }

    // MARK: - Shell Execution

    /// Splits a whitespace-separated command string (e.g. `"npx cdk"`) into argv.
    private func splitCommand(_ command: String) -> [String] {
        command.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func runShell(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws {
        guard let executable = arguments.first else {
            throw ContainerError.setupFailed(
                step: "CDKSetup",
                reason: "Empty command passed to runShell"
            )
        }
        let remainingArgs = Array(arguments.dropFirst())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + remainingArgs
        process.currentDirectoryURL = URL(fileURLWithPath: cdkAppPath)

        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        logger.debug(
            "Executing",
            metadata: [
                "command": "\(arguments.joined(separator: " "))",
                "cwd": "\(cdkAppPath)",
            ]
        )

        // Install the termination handler BEFORE launching so we don't race
        // against a fast-exiting process.
        let exitStatus: Int32 = await withCheckedContinuation {
            (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                // run() failed — terminationHandler will not fire, so resume
                // ourselves with a sentinel and clear the handler to be safe.
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if !stdout.isEmpty {
            logger.debug("stdout", metadata: ["output": "\(stdout)"])
        }
        if !stderr.isEmpty {
            logger.debug("stderr", metadata: ["output": "\(stderr)"])
        }

        guard exitStatus == 0 else {
            let combined = [stdout, stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw ContainerError.setupFailed(
                step: "CDKSetup",
                reason:
                    "\(arguments.joined(separator: " ")) exited with status \(exitStatus):\n\(combined)"
            )
        }
    }
}

// MARK: - OutputProducingSetup

extension CDKSetup: OutputProducingSetup {
    public func fetchOutputs(
        from container: RunningContainer
    ) async throws -> [String: String] {
        let cfSetup = CloudFormationSetup(
            templatePath: "",
            stackName: stackName,
            logger: logger
        )
        return try await cfSetup.fetchOutputs(from: container)
    }
}
