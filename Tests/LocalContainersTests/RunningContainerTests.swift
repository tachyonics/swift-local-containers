import Testing

@testable import LocalContainers

@Suite("RunningContainer")
struct RunningContainerTests {
    @Test("mappedPort returns the host port for a known container port")
    func mappedPortFound() throws {
        let container = RunningContainer(
            id: "abc123",
            name: "test",
            image: "nginx",
            ports: [
                ResolvedPortMapping(containerPort: 80, hostPort: 32768),
                ResolvedPortMapping(containerPort: 443, hostPort: 32769),
            ]
        )

        let port = try container.mappedPort(80)
        #expect(port == 32768)

        let port2 = try container.mappedPort(443)
        #expect(port2 == 32769)
    }

    @Test("mappedPort throws for an unknown container port")
    func mappedPortNotFound() {
        let container = RunningContainer(
            id: "abc123",
            name: "test",
            image: "nginx",
            ports: [ResolvedPortMapping(containerPort: 80, hostPort: 32768)]
        )

        #expect(throws: ContainerError.self) {
            try container.mappedPort(9999)
        }
    }

    @Test("Default host is 127.0.0.1")
    func defaultHost() {
        let container = RunningContainer(id: "abc", name: "test", image: "nginx")
        #expect(container.host == "127.0.0.1")
    }
}
