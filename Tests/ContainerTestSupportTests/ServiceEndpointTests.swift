import Testing

@testable import ContainerTestSupport
@testable import LocalContainers

@Suite("ServiceEndpoint")
struct ServiceEndpointTests {
    @Test("port(_:) returns mapped host port for a known container port")
    func portLookupFound() throws {
        let endpoint = ServiceEndpoint(
            host: "127.0.0.1",
            ports: [
                ResolvedPortMapping(containerPort: 8080, hostPort: 54321),
                ResolvedPortMapping(containerPort: 9000, hostPort: 54322),
            ]
        )

        #expect(try endpoint.port(8080) == 54321)
        #expect(try endpoint.port(9000) == 54322)
    }

    @Test("port(_:) throws portNotFound for an unmapped container port")
    func portLookupMissing() {
        let endpoint = ServiceEndpoint(
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: 54321)]
        )

        #expect(throws: ContainerError.self) {
            _ = try endpoint.port(9999)
        }
    }

    @Test("baseURL returns http://host:port for a single TCP port")
    func baseURLSingleTCP() {
        let endpoint = ServiceEndpoint(
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: 54321)]
        )

        #expect(endpoint.baseURL == "http://127.0.0.1:54321")
    }

    @Test("baseURL ignores UDP ports when computing single-port-ness")
    func baseURLIgnoresUDP() {
        let endpoint = ServiceEndpoint(
            host: "127.0.0.1",
            ports: [
                ResolvedPortMapping(containerPort: 8080, hostPort: 54321, protocol: .tcp),
                ResolvedPortMapping(containerPort: 5353, hostPort: 54322, protocol: .udp),
            ]
        )

        #expect(endpoint.baseURL == "http://127.0.0.1:54321")
    }

    @Test("init(from:) copies host and ports from a RunningContainer")
    func initFromRunningContainer() {
        let container = RunningContainer(
            id: "abc",
            name: "svc",
            image: "img:tag",
            host: "10.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 80, hostPort: 12345)]
        )

        let endpoint = ServiceEndpoint(from: container)

        #expect(endpoint.host == "10.0.0.1")
        #expect(endpoint.ports.count == 1)
        #expect(endpoint.ports[0].containerPort == 80)
        #expect(endpoint.ports[0].hostPort == 12345)
    }
}
