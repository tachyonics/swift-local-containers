import ContainerTestSupport
import DockerRuntime
import Foundation
import LocalContainers
import LocalStack
import Testing

/// Integration tests that exercise ``CDKSetup`` directly — the imperative
/// path: synth at test time, deploy to LocalStack, read outputs back.
///
/// Covers both imperative operating modes:
/// - `autoBootstrap: false` — SSM-stub fast path (assetless stacks only).
/// - `autoBootstrap: true` — full cdklocal bootstrap + deploy (asset-bearing
///   stacks). Slower (~30s bootstrap penalty) but supports Lambda inline
///   code, Docker image assets, etc.
///
/// The declarative manifest-driven path (build-time synth via the
/// `cdkapps[]` manifest entry + `@LocalStackContainer`) is covered
/// separately in `CDKIntegrationTests.swift` and only supports the
/// assetless SSM-stub flow.
@Suite(
    .tags(.integration, .localstack),
    .serialized,
    .enabled(
        if: dockerAvailable && npmAvailable,
        "Docker and npm are required"
    )
)
struct CDKSetupImperativeTests {
    @Test(
        "CDKSetup with autoBootstrap=false synthesizes an assetless CDK app, deploys it to LocalStack, and reads outputs"
    )
    func deployAssetlessCDKApp() async throws {
        let fixtureURL = imperativeCdkFixtureURL()
        try ensureCDKDependenciesInstalled(at: fixtureURL)

        let runtime = DockerContainerRuntime()
        // `ssm` is required because CloudFormationSetup auto-stubs the
        // bootstrap version SSM parameter when deploying CDK-synthesized
        // templates.
        let config = LocalStackContainer(
            services: ["s3", "cloudformation", "ssm"],
            environment: LocalStackContainer.environmentForwarding(
                overriding: LocalContainersConfig.values
            )
        ).configuration()

        try await runtime.pullImage(config.image.imageReference)
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

    @Test(
        "CDKSetup with autoBootstrap=true uses cdklocal to bootstrap LocalStack and deploy an asset-bearing stack"
    )
    func deployAssetBearingCDKApp() async throws {
        let fixtureURL = imperativeCdkFixtureURL()
        try ensureCDKDependenciesInstalled(at: fixtureURL)

        let runtime = DockerContainerRuntime()
        // No explicit services list — cdklocal bootstrap creates a
        // CDKToolkit stack that touches S3, IAM, SSM, and ECR. Simpler
        // to let LocalStack start its full default service set than
        // to enumerate the minimum required set.
        let config = LocalStackContainer(
            environment: LocalStackContainer.environmentForwarding(
                overriding: LocalContainersConfig.values
            )
        ).configuration()

        try await runtime.pullImage(config.image.imageReference)
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
            stackName: "CdkAssetIntegrationTestStack",
            autoBootstrap: true
        )

        try await setup.setUp(container: container)
        defer {
            Task { try? await setup.tearDown(container: container) }
        }

        let outputs = try await setup.fetchOutputs(from: container)
        // The fixture uses `s3_assets.Asset` to create a file asset
        // from `asset.txt`. CDK uploads it to the staging bucket during
        // deploy, and the stack's outputs expose the resulting bucket
        // name and object key. These values prove the full cdklocal
        // pipeline (bootstrap -> template asset publish -> file asset
        // publish -> CloudFormation create -> outputs readback) works
        // end-to-end against LocalStack.
        let assetBucket = try #require(outputs["AssetBucket"])
        let assetKey = try #require(outputs["AssetKey"])
        #expect(!assetBucket.isEmpty)
        #expect(!assetKey.isEmpty)
        // CDK stages assets in a bucket whose name starts with
        // `cdk-hnb659fds-assets-` by convention. Don't pin the exact
        // name (account/region suffix differs), just confirm the
        // prefix.
        #expect(assetBucket.hasPrefix("cdk-hnb659fds-assets-"))
        #expect(outputs["_awsEndpoint"]?.isEmpty == false)
    }

    @Test(
        "CDKSetup with autoBootstrap=true deploys a Lambda stack when Docker socket is mounted",
        .enabled(
            if: dockerSocketAvailable,
            "Docker socket at \(dockerSocketPath) is required for LocalStack Lambda execution"
        )
    )
    func deployLambdaCDKApp() async throws {
        let fixtureURL = imperativeCdkFixtureURL()
        try ensureCDKDependenciesInstalled(at: fixtureURL)

        let runtime = DockerContainerRuntime()
        // Mount the host Docker socket so LocalStack can spawn sibling
        // containers for Lambda runtime execution.
        let config = LocalStackContainer(
            environment: LocalStackContainer.environmentForwarding(
                overriding: LocalContainersConfig.values
            ),
            volumes: [
                VolumeMount(
                    hostPath: dockerSocketPath,
                    containerPath: "/var/run/docker.sock"
                )
            ]
        ).configuration()

        try await runtime.pullImage(config.image.imageReference)
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
            stackName: "CdkLambdaIntegrationTestStack",
            autoBootstrap: true
        )

        try await setup.setUp(container: container)
        defer {
            Task { try? await setup.tearDown(container: container) }
        }

        let outputs = try await setup.fetchOutputs(from: container)
        let functionName = try #require(outputs["FunctionName"])
        #expect(!functionName.isEmpty)
        #expect(outputs["_awsEndpoint"]?.isEmpty == false)
    }
}

// MARK: - Fixture helpers

private func imperativeCdkFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("cdk-app")
}

/// Runs `npm install` inside the fixture the first time it's needed.
/// Short-circuits on the presence of BOTH `node_modules/.bin/cdk` and
/// `node_modules/.bin/cdklocal`, because one test uses each. Checking
/// both ensures a stale node_modules from before `aws-cdk-local` was
/// added to `devDependencies` triggers a fresh install.
private func ensureCDKDependenciesInstalled(at fixtureURL: URL) throws {
    let cdkBinary =
        fixtureURL
        .appendingPathComponent("node_modules")
        .appendingPathComponent(".bin")
        .appendingPathComponent("cdk")
    let cdkLocalBinary =
        fixtureURL
        .appendingPathComponent("node_modules")
        .appendingPathComponent(".bin")
        .appendingPathComponent("cdklocal")
    if FileManager.default.fileExists(atPath: cdkBinary.path)
        && FileManager.default.fileExists(atPath: cdkLocalBinary.path)
    {
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
