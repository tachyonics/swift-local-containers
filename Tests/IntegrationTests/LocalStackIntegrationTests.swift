import ContainerTestSupport
import LocalContainers
import LocalStack
import Testing

struct LocalStackKey: ContainerKey {
    static let spec = ContainerSpec(
        LocalStackContainer(services: ["s3", "sqs"]).configuration()
    )
}

@Suite(.tags(.integration, .localstack))
struct LocalStackIntegrationTests {
    @Test("LocalStack container starts and exposes gateway port")
    func gatewayEndpoint() async throws {
        // This test requires a running container runtime (Docker or Containerization).
        // It is tagged .integration so it is skipped by default.
        //
        // To run:
        //   swift test --filter IntegrationTests
        //
        // The actual container lifecycle would be managed by ContainerTrait
        // once the runtime backends are fully implemented.

        let container = RunningContainer(
            id: "test-ls",
            name: "localstack",
            image: "localstack/localstack:latest",
            ports: [ResolvedPortMapping(containerPort: 4566, hostPort: 4566)]
        )

        let endpoint = try LocalStackEndpoint(container: container).gatewayEndpoint()
        #expect(endpoint == "http://127.0.0.1:4566")
    }
}
