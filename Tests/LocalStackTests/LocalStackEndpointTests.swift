import Testing

@testable import LocalContainers
@testable import LocalStack

@Suite("LocalStackEndpoint")
struct LocalStackEndpointTests {
    private static let container = RunningContainer(
        id: "ls-1",
        name: "localstack",
        image: "localstack/localstack:latest",
        host: "127.0.0.1",
        ports: [
            ResolvedPortMapping(containerPort: 4566, hostPort: 49152),
        ]
    )

    @Test("gatewayEndpoint returns correct URL with mapped port")
    func gatewayEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let url = try ep.gatewayEndpoint()

        #expect(url == "http://127.0.0.1:49152")
    }

    @Test("awsEndpoint returns same URL as gatewayEndpoint")
    func awsEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let gateway = try ep.gatewayEndpoint()
        let aws = try ep.awsEndpoint()

        #expect(gateway == aws)
    }

    @Test("endpoint(for:) returns gateway URL for any service")
    func serviceEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let url = try ep.endpoint(for: "s3")

        #expect(url == "http://127.0.0.1:49152")
    }

    @Test("Throws when gateway port is not mapped")
    func missingPort() {
        let container = RunningContainer(
            id: "ls-2",
            name: "localstack",
            image: "localstack/localstack:latest",
            ports: []
        )
        let ep = LocalStackEndpoint(container: container)

        #expect(throws: ContainerError.self) {
            try ep.gatewayEndpoint()
        }
    }

    @Test("Custom gateway port is respected")
    func customGatewayPort() throws {
        let container = RunningContainer(
            id: "ls-3",
            name: "localstack",
            image: "localstack/localstack:latest",
            ports: [
                ResolvedPortMapping(containerPort: 4510, hostPort: 49200),
            ]
        )
        let ep = LocalStackEndpoint(container: container, gatewayPort: 4510)
        let url = try ep.gatewayEndpoint()

        #expect(url == "http://127.0.0.1:49200")
    }
}
