import AsyncHTTPClient
import ContainerMacrosLib
import Foundation
import NIOCore
import Testing

@Containers
enum CFContainers {
    @LocalStackContainer(stackName: "integration-test")
    static var bucketStack: TestS3BucketOutputs
}

@Suite(
    CFContainers.containerTrait,
    .tags(.integration, .localstack),
    .enabled(if: dockerAvailable, "Docker is required")
)
struct CloudFormationIntegrationTests {
    @Test("Deploys CF stack, retrieves outputs, and interacts with S3 bucket")
    func deployAndInteract() async throws {
        #expect(!CFContainers.bucketStack.bucketName.isEmpty)

        let endpoint = CFContainers.bucketStack.awsEndpoint
        let bucket = CFContainers.bucketStack.bucketName
        let objectUrl = "\(endpoint)/\(bucket)/test-key"

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
