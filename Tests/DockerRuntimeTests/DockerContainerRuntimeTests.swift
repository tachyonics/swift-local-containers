import Foundation
import Testing

@testable import DockerRuntime
@testable import LocalContainers

@Suite("DockerContainerRuntime.buildCreateRequest")
struct DockerContainerRuntimeBuildRequestTests {
    private let runtime = DockerContainerRuntime()

    @Test("Minimal config produces request with image only")
    func minimalConfig() {
        let config = ContainerConfiguration(image: "nginx:latest")
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.image == "nginx:latest")
        #expect(request.env == nil)
        #expect(request.cmd == nil)
        #expect(request.exposedPorts == nil)
        #expect(request.healthcheck == nil)
        #expect(request.hostConfig?.portBindings == nil)
        #expect(request.hostConfig?.binds == nil)
    }

    @Test("Environment variables are formatted as KEY=VALUE")
    func environmentVariables() {
        let config = ContainerConfiguration(
            image: "postgres:16",
            environment: ["POSTGRES_PASSWORD": "secret", "POSTGRES_DB": "test"]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.env != nil)
        #expect(request.env?.count == 2)
        #expect(request.env?.contains("POSTGRES_PASSWORD=secret") == true)
        #expect(request.env?.contains("POSTGRES_DB=test") == true)
    }

    @Test("Command override is passed through")
    func commandOverride() {
        let config = ContainerConfiguration(
            image: "postgres:16",
            command: ["postgres", "-c", "log_statement=all"]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.cmd == ["postgres", "-c", "log_statement=all"])
    }

    @Test("Port mappings generate ExposedPorts and PortBindings")
    func portMappings() {
        let config = ContainerConfiguration(
            image: "nginx",
            ports: [
                PortMapping(containerPort: 80, hostPort: 8080),
                PortMapping(containerPort: 443),
            ]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.exposedPorts?["80/tcp"] != nil)
        #expect(request.exposedPorts?["443/tcp"] != nil)

        let binding80 = request.hostConfig?.portBindings?["80/tcp"]
        #expect(binding80?.count == 1)
        #expect(binding80?[0].hostPort == "8080")

        // No host port specified → empty string (Docker assigns random port)
        let binding443 = request.hostConfig?.portBindings?["443/tcp"]
        #expect(binding443?[0].hostPort == "")
    }

    @Test("UDP port uses correct protocol key")
    func udpPort() {
        let config = ContainerConfiguration(
            image: "dns",
            ports: [PortMapping(containerPort: 53, protocol: .udp)]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.exposedPorts?["53/udp"] != nil)
        #expect(request.hostConfig?.portBindings?["53/udp"] != nil)
    }

    @Test("Volume mounts generate Binds strings")
    func volumeMounts() {
        let config = ContainerConfiguration(
            image: "app",
            volumes: [
                VolumeMount(hostPath: "/data", containerPath: "/var/data"),
                VolumeMount(hostPath: "/config", containerPath: "/etc/config", readOnly: true),
            ]
        )
        let request = runtime.buildCreateRequest(from: config)

        let binds = request.hostConfig?.binds
        #expect(binds?.count == 2)
        #expect(binds?.contains("/data:/var/data") == true)
        #expect(binds?.contains("/config:/etc/config:ro") == true)
    }

    @Test("Health check is converted with nanosecond intervals")
    func healthCheck() {
        let config = ContainerConfiguration(
            image: "app",
            healthCheck: HealthCheckConfig(
                test: ["CMD", "curl", "-f", "http://localhost/"],
                interval: .seconds(10),
                timeout: .seconds(5),
                retries: 3,
                startPeriod: .seconds(2)
            )
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.healthcheck?.test == ["CMD", "curl", "-f", "http://localhost/"])
        #expect(request.healthcheck?.interval == 10_000_000_000)
        #expect(request.healthcheck?.timeout == 5_000_000_000)
        #expect(request.healthcheck?.retries == 3)
        #expect(request.healthcheck?.startPeriod == 2_000_000_000)
    }

    @Test("Full config round-trips through JSON encoding")
    func fullConfigJsonRoundTrip() throws {
        let config = ContainerConfiguration(
            image: "app:v2",
            ports: [PortMapping(containerPort: 8080, hostPort: 9090)],
            environment: ["FOO": "bar"],
            volumes: [VolumeMount(hostPath: "/tmp", containerPath: "/data")],
            command: ["serve", "--port", "8080"]
        )
        let request = runtime.buildCreateRequest(from: config)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateContainerRequest.self, from: data)

        #expect(decoded.image == "app:v2")
        #expect(decoded.cmd == ["serve", "--port", "8080"])
        #expect(decoded.env == ["FOO=bar"])
        #expect(decoded.exposedPorts?["8080/tcp"] != nil)
        #expect(decoded.hostConfig?.portBindings?["8080/tcp"]?[0].hostPort == "9090")
        #expect(decoded.hostConfig?.binds == ["/tmp:/data"])
    }
}
