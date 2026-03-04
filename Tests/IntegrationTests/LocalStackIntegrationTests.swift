import AsyncHTTPClient
import ContainerTestSupport
import DockerRuntime
import Foundation
import LocalContainers
import NIOCore
import Testing

@testable import LocalStack

// MARK: - Shared template path

private let s3BucketTemplatePath: String = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("s3-bucket-template.json")
        .path
}()

// MARK: - ContainerTrait-based CloudFormation test

struct LocalStackCFKey: ContainerKey {
    static let spec = ContainerSpec(
        LocalStackContainer(services: ["s3", "cloudformation"]).configuration(),
        setups: [
            CloudFormationSetup(
                templatePath: s3BucketTemplatePath,
                stackName: "trait-test-stack",
                parameters: ["BucketName": "trait-test-bucket"],
                timeout: .seconds(60)
            )
        ]
    )
}

@Suite(
    .containers(LocalStackCFKey.self),
    .tags(.integration, .localstack),
    .enabled(if: dockerAvailable, "Docker is required")
)
struct CloudFormationContainerTraitTests {
    @Test("S3 bucket created by ContainerTrait setup is usable")
    func traitManagedS3() async throws {
        let ctx = try #require(ContainerTestContext.current)
        let container = try ctx[LocalStackCFKey.self]
        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()

        // PUT an object
        let objectBody = "hello from container trait test"
        var putRequest = HTTPClientRequest(url: "\(endpoint)/trait-test-bucket/test-key")
        putRequest.method = .PUT
        putRequest.body = .bytes(ByteBuffer(string: objectBody))
        let putResponse = try await HTTPClient.shared.execute(putRequest, timeout: .seconds(10))
        #expect((200..<300).contains(Int(putResponse.status.code)))

        // GET it back
        var getRequest = HTTPClientRequest(url: "\(endpoint)/trait-test-bucket/test-key")
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(getRequest, timeout: .seconds(10))
        let body = try await getResponse.body.collect(upTo: 1_024 * 1_024)
        #expect(String(buffer: body) == objectBody)
    }
}

// MARK: - Manual lifecycle tests

@Suite(.tags(.integration, .localstack))
struct LocalStackIntegrationTests {
    @Test("LocalStack container starts and exposes gateway port")
    func gatewayEndpoint() async throws {
        let container = RunningContainer(
            id: "test-ls",
            name: "localstack",
            image: "localstack/localstack:latest",
            ports: [ResolvedPortMapping(containerPort: 4566, hostPort: 4566)]
        )

        let endpoint = try LocalStackEndpoint(container: container).gatewayEndpoint()
        #expect(endpoint == "http://127.0.0.1:4566")
    }

    // MARK: - CloudFormation + S3

    @Test(
        "CloudFormation deploys S3 bucket and objects can be stored and retrieved",
        .enabled(if: dockerAvailable, "Docker is required")
    )
    func cloudFormationS3() async throws {
        let runtime = DockerContainerRuntime()
        let lsConfig = LocalStackContainer(
            services: ["s3", "cloudformation"]
        ).configuration()

        try await runtime.pullImage(lsConfig.image)
        let container = try await runtime.startContainer(from: lsConfig)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: lsConfig,
            runtime: runtime
        )

        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()

        // Deploy via CloudFormationSetup using the checked-in template
        let cfSetup = CloudFormationSetup(
            templatePath: s3BucketTemplatePath,
            stackName: "integration-test-stack",
            parameters: ["BucketName": "integration-test-bucket"],
            timeout: .seconds(60),
            pollInterval: .seconds(2)
        )
        try await cfSetup.setUp(container: container)

        // PUT an object to the S3 bucket
        let objectBody = "hello from integration test"
        var putRequest = HTTPClientRequest(
            url: "\(endpoint)/integration-test-bucket/test-key"
        )
        putRequest.method = .PUT
        putRequest.body = .bytes(ByteBuffer(string: objectBody))
        let putResponse = try await HTTPClient.shared.execute(putRequest, timeout: .seconds(10))
        #expect((200..<300).contains(Int(putResponse.status.code)))

        // GET the object back and verify contents
        var getRequest = HTTPClientRequest(
            url: "\(endpoint)/integration-test-bucket/test-key"
        )
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(getRequest, timeout: .seconds(10))
        let body = try await getResponse.body.collect(upTo: 1_024 * 1_024)
        let retrieved = String(buffer: body)
        #expect(retrieved == objectBody)

        // Tear down (exercises deleteStack)
        try await cfSetup.tearDown(container: container)
    }

    // MARK: - CDK + S3

    @Test(
        "CDK deploys S3 bucket via synth and CloudFormation",
        .enabled(if: dockerAvailable, "Docker is required"),
        .enabled(if: npmAvailable, "npm is required")
    )
    func cdkS3() async throws {
        let runtime = DockerContainerRuntime()
        let lsConfig = LocalStackContainer(
            services: ["s3", "cloudformation"]
        ).configuration()

        try await runtime.pullImage(lsConfig.image)
        let container = try await runtime.startContainer(from: lsConfig)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: lsConfig,
            runtime: runtime
        )

        let endpoint = try LocalStackEndpoint(container: container).awsEndpoint()

        // Create a minimal CDK app in a temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdk-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let cdkJson = """
            {
              "app": "node app.js"
            }
            """
        try cdkJson.write(
            to: tempDir.appendingPathComponent("cdk.json"),
            atomically: true,
            encoding: .utf8
        )

        let appJs = """
            const cdk = require('aws-cdk-lib');
            const s3 = require('aws-cdk-lib/aws-s3');
            const app = new cdk.App();
            const stack = new cdk.Stack(app, 'CdkTestStack');
            new s3.Bucket(stack, 'TestBucket', { bucketName: 'cdk-test-bucket' });
            """
        try appJs.write(
            to: tempDir.appendingPathComponent("app.js"),
            atomically: true,
            encoding: .utf8
        )

        // Install CDK dependencies
        let cdkSetupHelper = CDKSetup(
            cdkAppPath: tempDir.path,
            stackName: "CdkTestStack"
        )

        try await cdkSetupHelper.runShell(
            "cd \(tempDir.path) && npm init -y && npm install aws-cdk-lib constructs"
        )

        // Deploy via CDKSetup
        let cdkSetup = CDKSetup(
            cdkAppPath: tempDir.path,
            stackName: "CdkTestStack"
        )
        try await cdkSetup.setUp(container: container)

        // PUT an object to the CDK-created S3 bucket
        let objectBody = "hello from cdk integration test"
        var putRequest = HTTPClientRequest(
            url: "\(endpoint)/cdk-test-bucket/test-key"
        )
        putRequest.method = .PUT
        putRequest.body = .bytes(ByteBuffer(string: objectBody))
        let putResponse = try await HTTPClient.shared.execute(putRequest, timeout: .seconds(10))
        #expect((200..<300).contains(Int(putResponse.status.code)))

        // GET the object back and verify contents
        var getRequest = HTTPClientRequest(
            url: "\(endpoint)/cdk-test-bucket/test-key"
        )
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(getRequest, timeout: .seconds(10))
        let body = try await getResponse.body.collect(upTo: 1_024 * 1_024)
        let retrieved = String(buffer: body)
        #expect(retrieved == objectBody)

        // Tear down (exercises deleteStack)
        try await cdkSetup.tearDown(container: container)

        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDir)
    }
}
