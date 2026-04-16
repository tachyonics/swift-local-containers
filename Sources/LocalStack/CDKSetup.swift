import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging
import NIOCore

/// A ``ContainerSetup`` that synthesizes a CDK stack and deploys it to a
/// LocalStack container.
///
/// Use this when the CDK code is the source of truth and you want tests to
/// always use the latest infrastructure definition. Two operating modes:
///
/// ## `autoBootstrap: false` — fast path, assetless stacks only (default)
///
/// Runs `cdk synth` locally to produce a CloudFormation template, then
/// hands the template to ``CloudFormationSetup`` which deploys it via the
/// LocalStack CloudFormation API. ``CloudFormationSetup`` automatically
/// stubs the `/cdk-bootstrap/hnb659fds/version` SSM parameter (see
/// ``BootstrapVersionStub``) so CDK's default synthesizer
/// ``CheckBootstrapVersion`` rule passes without a real bootstrap stack.
///
/// This is the right choice for stacks containing only "inline" resources:
/// DynamoDB tables, SQS queues, SNS topics, Step Functions, S3 buckets,
/// IAM roles, etc. Anything that doesn't require file or container image
/// uploads.
///
/// ## `autoBootstrap: true` — full CDK flow, supports asset-bearing stacks
///
/// Delegates to `cdklocal` (the `aws-cdk-local` npm package) which wraps
/// the regular CDK CLI and routes every AWS API call at LocalStack. Runs
/// `cdklocal bootstrap` to create a real `CDKToolkit` stack inside
/// LocalStack (including the assets S3 bucket and ECR repo), then
/// `cdklocal deploy` to upload assets and create the application stack.
///
/// Use this when the stack uses file or Docker image assets:
/// `lambda.Code.fromAsset(...)`, `ecs.ContainerImage.fromAsset(...)`,
/// bundled CloudFormation init scripts, etc.
///
/// ### Tradeoffs
///
/// - **Slower**: `cdklocal bootstrap` adds ~30 seconds per test run because
///   it creates and waits for the `CDKToolkit` stack in LocalStack.
/// - **Extra npm dependency**: requires `aws-cdk-local` in the CDK app's
///   `devDependencies`.
/// - **Third-party tool**: `cdklocal` is maintained by the LocalStack team,
///   not AWS. It handles common CDK patterns well; exotic asset types may
///   have sharp edges.
public struct CDKSetup: ContainerSetup {
    /// Directory containing the CDK app (must contain `cdk.json`).
    public let cdkAppPath: String

    /// CDK stack to synthesize.
    public let stackName: String

    /// Command to invoke the CDK CLI (e.g. `"npx cdk"` or `"cdk"`).
    /// Used by the `autoBootstrap: false` path.
    public let cdkCommand: String

    /// Command to invoke the `cdklocal` CLI (e.g. `"npx cdklocal"`).
    /// Used by the `autoBootstrap: true` path.
    public let cdkLocalCommand: String

    /// CloudFormation parameters to pass during deployment.
    public let parameters: [String: String]

    /// Whether to run the full `cdklocal bootstrap` + `cdklocal deploy`
    /// flow against LocalStack. Default `false` — use the fast SSM-stub
    /// path which works for any assetless stack. Set to `true` if your
    /// CDK app uses Lambda asset code, Docker image assets, or other
    /// CDK features that require a real bootstrap stack to be present.
    public let autoBootstrap: Bool

    private let logger: Logger

    public init(
        cdkAppPath: String,
        stackName: String,
        cdkCommand: String = "npx cdk",
        cdkLocalCommand: String = "npx cdklocal",
        parameters: [String: String] = [:],
        autoBootstrap: Bool = false,
        logger: Logger = Logger(label: "CDKSetup")
    ) {
        self.cdkAppPath = cdkAppPath
        self.stackName = stackName
        self.cdkCommand = cdkCommand
        self.cdkLocalCommand = cdkLocalCommand
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
                "mode": "\(autoBootstrap ? "cdklocal" : "ssm-stub")",
            ]
        )

        if autoBootstrap {
            // Full CDK flow via cdklocal. Bootstraps a real CDKToolkit
            // stack in LocalStack, then deploys — uploading any file or
            // image assets to the in-LocalStack staging locations.
            try await cdkLocalBootstrap(endpoint: endpoint)
            try await cdkLocalDeploy(endpoint: endpoint)
        } else {
            // Fast path: synth locally, hand the template to
            // CloudFormationSetup, which auto-stubs the bootstrap version
            // SSM parameter when it sees the CDK marker in the template
            // body. Works for any assetless stack. See
            // ``BootstrapVersionStub`` for the rationale.
            let templatePath = try await synth(endpoint: endpoint)
            let cfSetup = CloudFormationSetup(
                templatePath: templatePath,
                stackName: stackName,
                parameters: parameters,
                logger: logger
            )
            try await cfSetup.setUp(container: container)
        }
    }

    public func tearDown(container: RunningContainer) async throws {
        // `CloudFormationSetup.tearDown` just issues `DeleteStack` against
        // LocalStack. That works for stacks deployed via either path —
        // the SSM-stub route and the cdklocal route both put the stack
        // into LocalStack's CloudFormation service, so DeleteStack
        // cleans it up regardless. Leftover assets in LocalStack's
        // staging bucket are disposed of when the container shuts down.
        let cfSetup = CloudFormationSetup(
            templatePath: "",
            stackName: stackName,
            logger: logger
        )
        try await cfSetup.tearDown(container: container)
    }

    // MARK: - CDK CLI Invocations

    private func cdkLocalBootstrap(endpoint: String) async throws {
        logger.info("Running cdklocal bootstrap")
        let arguments =
            splitCommand(cdkLocalCommand)
            + ["bootstrap", "aws://000000000000/us-east-1"]
        try await runShell(
            arguments,
            environment: cdkEnvironment(endpoint: endpoint)
        )
    }

    private func cdkLocalDeploy(endpoint: String) async throws {
        logger.info("Running cdklocal deploy")
        var arguments =
            splitCommand(cdkLocalCommand)
            + ["deploy", stackName, "--require-approval", "never"]

        // Pass any user-supplied CloudFormation parameters through to
        // `cdklocal deploy --parameters <stack>:Key=Value`.
        for (key, value) in parameters.sorted(by: { $0.key < $1.key }) {
            arguments.append("--parameters")
            arguments.append("\(stackName):\(key)=\(value)")
        }

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
        // We set both the generic `AWS_ENDPOINT_URL` AND the
        // service-specific `AWS_ENDPOINT_URL_S3` because `cdk-assets`
        // (the component the CDK CLI uses to upload file assets to the
        // staging bucket) reads the S3-specific variable and doesn't
        // fall back to the generic one.
        //
        // The S3 URL needs the `s3.` subdomain prefix
        // (`https://s3.localhost.localstack.cloud:<port>`) rather than
        // the plain gateway URL. Without it, when the AWS SDK
        // constructs virtual-hosted-style requests, the resulting
        // `<bucket>.localhost.localstack.cloud` URL reaches LocalStack's
        // router but can't be identified as an S3 operation — LocalStack
        // returns "unknown operation" and falls back to XML-parsing the
        // JSON asset body. The `s3.` prefix is the sentinel LocalStack
        // uses to route virtual-hosted S3 traffic correctly, mirroring
        // cdklocal's own default (`s3.localhost.localstack.cloud:4566`).
        let s3Endpoint = Self.injectSubdomain("s3", into: endpoint)
        return [
            "AWS_ENDPOINT_URL": endpoint,
            "AWS_ENDPOINT_URL_S3": s3Endpoint,
            "CDK_DEFAULT_ACCOUNT": "000000000000",
            "CDK_DEFAULT_REGION": "us-east-1",
            "AWS_ACCESS_KEY_ID": "test",
            "AWS_SECRET_ACCESS_KEY": "test",
            "AWS_REGION": "us-east-1",
        ]
    }

    /// Given a URL like `https://localhost.localstack.cloud:65151`, returns
    /// `https://s3.localhost.localstack.cloud:65151` (injecting the given
    /// subdomain immediately after the scheme). Used to build
    /// service-specific LocalStack URLs from the generic gateway URL.
    private static func injectSubdomain(_ subdomain: String, into url: String) -> String {
        guard let schemeEnd = url.range(of: "://") else {
            return url
        }
        var result = url
        result.insert(contentsOf: "\(subdomain).", at: schemeEnd.upperBound)
        return result
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
