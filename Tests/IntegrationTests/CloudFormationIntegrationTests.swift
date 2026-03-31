import AsyncHTTPClient
import ContainerMacrosLib
import ContainerTestSupport
import Foundation
import NIOCore
import Testing

@Containers
struct CFContainers {
    @LocalStackContainer(stackName: "integration-test")
    var bucketStack: TestS3BucketOutputs
}

@Suite(
    CFContainers.containerTrait,
    .tags(.integration, .localstack),
    .enabled(if: containerRuntimeAvailable, "Container runtime is required")
)
struct CloudFormationIntegrationTests {
    let containers = CFContainers()

    @Test("Deploys CF stack, retrieves outputs, and interacts with S3 bucket")
    func deployAndInteract() async throws {
        let bucketStack = containers.bucketStack
        #expect(!bucketStack.bucketName.isEmpty)

        let objectUrl = "\(bucketStack.awsEndpoint)/\(bucketStack.bucketName)/test-key"

        // PUT an object into the bucket via LocalStack S3 API
        var putRequest = HTTPClientRequest(url: objectUrl)
        putRequest.method = .PUT
        putRequest.body = .bytes(Data("hello from integration test".utf8))
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
        #expect(String(buffer: body) == "hello from integration test")
    }
}
