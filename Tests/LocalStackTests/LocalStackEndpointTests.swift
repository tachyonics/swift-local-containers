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
            ResolvedPortMapping(containerPort: 4566, hostPort: 49152)
        ]
    )

    @Test("gatewayEndpoint returns correct URL with mapped port")
    func gatewayEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let url = try ep.gatewayEndpoint()

        #expect(url == "http://127.0.0.1:49152")
    }

    @Test("awsEndpoint returns HTTPS URL with localstackHostname")
    func awsEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let aws = try ep.awsEndpoint()

        #expect(aws == "https://localhost.localstack.cloud:49152")
    }

    @Test("endpoint(for:) returns the awsEndpoint for any service")
    func serviceEndpoint() throws {
        let ep = LocalStackEndpoint(container: Self.container)
        let url = try ep.endpoint(for: "s3")

        #expect(url == "https://localhost.localstack.cloud:49152")
    }

    @Test("awsEndpointForSiblings uses container IP + container gateway port")
    func awsEndpointForSiblings() throws {
        let container = RunningContainer(
            id: "ls-4",
            name: "localstack",
            image: "localstack/localstack:latest",
            host: "127.0.0.1",
            bridgeGateway: "172.17.0.1",
            bridgeIPAddress: "172.17.0.2",
            ports: [ResolvedPortMapping(containerPort: 4566, hostPort: 49152)]
        )
        let ep = LocalStackEndpoint(container: container)

        #expect(try ep.awsEndpointForSiblings() == "http://172.17.0.2:4566")
    }

    @Test("awsEndpointForSiblings honours custom gateway port")
    func awsEndpointForSiblingsCustomPort() throws {
        let container = RunningContainer(
            id: "ls-5",
            name: "localstack",
            image: "localstack/localstack:latest",
            bridgeIPAddress: "172.17.0.4",
            ports: [ResolvedPortMapping(containerPort: 4510, hostPort: 49200)]
        )
        let ep = LocalStackEndpoint(container: container, gatewayPort: 4510)

        #expect(try ep.awsEndpointForSiblings() == "http://172.17.0.4:4510")
    }

    @Test("awsEndpointForSiblings throws when bridge IP is unavailable")
    func awsEndpointForSiblingsNoBridgeIP() {
        let ep = LocalStackEndpoint(container: Self.container)

        #expect(throws: ContainerError.self) {
            try ep.awsEndpointForSiblings()
        }
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
                ResolvedPortMapping(containerPort: 4510, hostPort: 49200)
            ]
        )
        let ep = LocalStackEndpoint(container: container, gatewayPort: 4510)
        let url = try ep.gatewayEndpoint()

        #expect(url == "http://127.0.0.1:49200")
    }
}
