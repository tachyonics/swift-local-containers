import Testing

@testable import LocalContainers

@Suite("ContainerConfiguration")
struct ContainerConfigurationTests {
    @Test("Default configuration has sensible defaults")
    func defaultConfiguration() {
        let config = ContainerConfiguration(image: "nginx:latest")

        #expect(config.image == "nginx:latest")
        #expect(config.ports.isEmpty)
        #expect(config.environment.isEmpty)
        #expect(config.volumes.isEmpty)
        #expect(config.name == nil)
        #expect(config.command == nil)
        #expect(config.healthCheck == nil)
    }

    @Test("Configuration preserves all fields")
    func fullConfiguration() {
        let config = ContainerConfiguration(
            image: "postgres:16",
            ports: [PortMapping(containerPort: 5432, hostPort: 15432)],
            environment: ["POSTGRES_PASSWORD": "test"],
            volumes: [VolumeMount(hostPath: "/tmp/data", containerPath: "/var/lib/data")],
            name: "test-postgres",
            command: ["postgres", "-c", "log_statement=all"]
        )

        #expect(config.image == "postgres:16")
        #expect(config.ports.count == 1)
        #expect(config.ports[0].containerPort == 5432)
        #expect(config.ports[0].hostPort == 15432)
        #expect(config.environment["POSTGRES_PASSWORD"] == "test")
        #expect(config.volumes.count == 1)
        #expect(config.volumes[0].readOnly == false)
        #expect(config.name == "test-postgres")
        #expect(config.command?.count == 3)
    }

    @Test("PortMapping defaults to TCP with no host port")
    func portMappingDefaults() {
        let mapping = PortMapping(containerPort: 8080)

        #expect(mapping.containerPort == 8080)
        #expect(mapping.hostPort == nil)
        #expect(mapping.protocol == .tcp)
    }

    @Test("PortMapping supports UDP")
    func udpPortMapping() {
        let mapping = PortMapping(containerPort: 53, protocol: .udp)

        #expect(mapping.protocol == .udp)
    }

    @Test("VolumeMount supports read-only")
    func readOnlyVolume() {
        let vol = VolumeMount(hostPath: "/config", containerPath: "/etc/config", readOnly: true)

        #expect(vol.readOnly == true)
    }
}
