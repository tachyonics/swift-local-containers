import AsyncHTTPClient
import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import NIOCore
import Testing

/// Declarative integration test that exercises the full CDK codegen pipeline:
/// the `.local-containers/codegen.json` manifest declares a `cdkapps[]` entry
/// pointing at `Resources/cdk-app`, the `ContainerCodeGen` build plugin runs
/// `npm install` + `cdk synth` at build time, and the synthesized template
/// flows through the same staging + `StackOutputs` generation pipeline as a
/// handwritten CloudFormation template. At test time, `@LocalStackContainer`
/// wires `CloudFormationSetup` against the staged template — which then
/// auto-stubs the CDK bootstrap SSM parameter because the template body
/// contains the `/cdk-bootstrap/hnb659fds/version` marker.
///
/// The imperative `CDKSetup` path is covered separately by
/// `CDKSetupImperativeTests.swift`.
@Containers
struct CDKContainers {
    @LocalStackContainer(stackName: "cdk-integration-test")
    var cdkStack: CdkIntegrationTestOutputs
}

@Suite(
    CDKContainers.containerTrait,
    .tags(.integration, .localstack),
    .enabled(if: containerRuntimeAvailable, "Container runtime is required"),
    .enabled(
        if: localStackAuthTokenAvailable,
        "LOCALSTACK_AUTH_TOKEN is required (set it in the environment or in .local-containers/env)"
    )
)
struct CDKIntegrationTests {
    let containers = CDKContainers()

    @Test("Deploys CDK-synthesized stack, retrieves outputs, and interacts with S3 bucket")
    func deployAndInteract() async throws {
        let cdkStack = containers.cdkStack
        #expect(!cdkStack.bucketName.isEmpty)

        let objectUrl = "\(cdkStack.awsEndpoint)/\(cdkStack.bucketName)/test-key"

        // PUT an object into the bucket via LocalStack S3 API
        var putRequest = HTTPClientRequest(url: objectUrl)
        putRequest.method = .PUT
        putRequest.body = .bytes(Data("hello from cdk integration test".utf8))
        let putResponse = try await HTTPClient.shared.execute(
            putRequest,
            timeout: .seconds(10)
        )
        #expect(putResponse.status == .ok)

        // GET it back and verify
        var getRequest = HTTPClientRequest(url: objectUrl)
        getRequest.method = .GET
        let getResponse = try await HTTPClient.shared.execute(
            getRequest,
            timeout: .seconds(10)
        )
        let body = try await getResponse.body.collect(upTo: 1024 * 1024)
        #expect(String(buffer: body) == "hello from cdk integration test")
    }
}
