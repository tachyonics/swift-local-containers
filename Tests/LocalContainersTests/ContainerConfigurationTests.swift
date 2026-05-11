import Logging
import Testing

@testable import LocalContainers

@Suite("ContainerConfiguration")
struct ContainerConfigurationTests {
    @Test("Default configuration has sensible defaults")
    func defaultConfiguration() {
        let config = ContainerConfiguration(image: "nginx:latest")

        #expect(config.image.imageReference == "nginx:latest")
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

        #expect(config.image.imageReference == "postgres:16")
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

    @Test("containerLogLevel defaults to nil")
    func containerLogLevelDefaultsToNil() {
        let config = ContainerConfiguration(image: "nginx:latest")
        #expect(config.containerLogLevel == nil)
    }

    @Test("containerLogLevel is preserved when set on init")
    func containerLogLevelOnInit() {
        let config = ContainerConfiguration(
            image: "nginx:latest",
            containerLogLevel: .info
        )
        #expect(config.containerLogLevel == .info)
    }

    @Test("with(containerLogLevel:) replaces the level and preserves other fields")
    func withContainerLogLevelReplaces() {
        let original = ContainerConfiguration(
            image: "postgres:16",
            ports: [PortMapping(containerPort: 5432, hostPort: 15432)],
            environment: ["POSTGRES_PASSWORD": "test"],
            volumes: [VolumeMount(hostPath: "/tmp/data", containerPath: "/var/lib/data")],
            name: "test-postgres",
            command: ["postgres"],
            waitStrategy: .httpGet(path: "/ready"),
            healthCheck: HealthCheckConfig(test: ["CMD", "pg_isready"]),
            waitTimeout: .seconds(30),
            containerLogLevel: .debug
        )

        let updated = original.with(containerLogLevel: .warning)

        #expect(updated.containerLogLevel == .warning)
        // Every other field is preserved.
        #expect(updated.image.imageReference == "postgres:16")
        #expect(updated.ports == original.ports)
        #expect(updated.environment == original.environment)
        #expect(updated.volumes == original.volumes)
        #expect(updated.name == "test-postgres")
        #expect(updated.command == ["postgres"])
        #expect(updated.waitTimeout == .seconds(30))
    }

    @Test("with(containerLogLevel:) can clear the level back to nil")
    func withContainerLogLevelClears() {
        let original = ContainerConfiguration(
            image: "nginx:latest",
            containerLogLevel: .info
        )
        #expect(original.with(containerLogLevel: nil).containerLogLevel == nil)
    }
}
