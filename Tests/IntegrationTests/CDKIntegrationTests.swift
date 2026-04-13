import ContainerTestSupport
import DockerRuntime
import Foundation
import LocalContainers
import LocalStack
import Testing

/// Integration test that exercises `CDKSetup` end-to-end: `cdk synth`
/// against a tiny fixture app, deploy to LocalStack, read outputs back.
///
/// The `cdk bootstrap` step is intentionally disabled — bootstrap against
/// LocalStack is flaky without `cdklocal`, and a basic S3-only stack does
/// not need a bootstrap stack present.
@Suite(
    .tags(.integration, .localstack),
    .enabled(
        if: dockerAvailable && npmAvailable,
        "Docker and npm are required"
    )
)
struct CDKIntegrationTests {
    @Test("CDKSetup synthesizes a CDK app, deploys it to LocalStack, and reads outputs")
    func deployCDKApp() async throws {
        let fixtureURL = cdkFixtureURL()
        try ensureCDKDependenciesInstalled(at: fixtureURL)

        let runtime = DockerContainerRuntime()
        // `ssm` is required because CDKSetup stubs the bootstrap version
        // SSM parameter before deploying. See CDKSetup.stubBootstrapVersion.
        let config = LocalStackContainer(
            services: ["s3", "cloudformation", "ssm"],
            environment: LocalStackContainer.environmentForwarding(
                overriding: LocalContainersConfig.values
            )
        ).configuration()

        try await runtime.pullImage(config.image)
        let container = try await runtime.startContainer(from: config)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        let setup = CDKSetup(
            cdkAppPath: fixtureURL.path,
            stackName: "CdkIntegrationTestStack",
            autoBootstrap: false
        )

        try await setup.setUp(container: container)
        defer {
            Task { try? await setup.tearDown(container: container) }
        }

        let outputs = try await setup.fetchOutputs(from: container)
        #expect(outputs["BucketName"] == "cdk-integration-test-bucket")
        #expect(outputs["_awsEndpoint"]?.isEmpty == false)
    }
}

// MARK: - Fixture helpers

private func cdkFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("cdk-app")
}

/// Runs `npm install` inside the fixture the first time it's needed. Subsequent
/// invocations short-circuit on the presence of `node_modules/aws-cdk-lib`.
private func ensureCDKDependenciesInstalled(at fixtureURL: URL) throws {
    let marker =
        fixtureURL
        .appendingPathComponent("node_modules")
        .appendingPathComponent("aws-cdk-lib")
    if FileManager.default.fileExists(atPath: marker.path) {
        return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["npm", "install", "--no-audit", "--no-fund", "--silent"]
    process.currentDirectoryURL = fixtureURL
    process.standardOutput = FileHandle.nullDevice
    process.standardError = Pipe()

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let stderr =
            (process.standardError as? Pipe).flatMap {
                try? $0.fileHandleForReading.readToEnd()
            }.flatMap {
                String(data: $0, encoding: .utf8)
            } ?? ""
        throw CDKIntegrationTestError.npmInstallFailed(
            status: process.terminationStatus,
            stderr: stderr
        )
    }
}

private enum CDKIntegrationTestError: Error, CustomStringConvertible {
    case npmInstallFailed(status: Int32, stderr: String)

    var description: String {
        switch self {
        case .npmInstallFailed(let status, let stderr):
            return "npm install failed with status \(status): \(stderr)"
        }
    }
}
