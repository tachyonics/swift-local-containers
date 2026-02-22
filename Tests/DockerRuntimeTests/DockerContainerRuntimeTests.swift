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

        #expect(request.Image == "nginx:latest")
        #expect(request.Env == nil)
        #expect(request.Cmd == nil)
        #expect(request.ExposedPorts == nil)
        #expect(request.Healthcheck == nil)
        #expect(request.HostConfig?.PortBindings == nil)
        #expect(request.HostConfig?.Binds == nil)
    }

    @Test("Environment variables are formatted as KEY=VALUE")
    func environmentVariables() {
        let config = ContainerConfiguration(
            image: "postgres:16",
            environment: ["POSTGRES_PASSWORD": "secret", "POSTGRES_DB": "test"]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.Env != nil)
        #expect(request.Env?.count == 2)
        #expect(request.Env?.contains("POSTGRES_PASSWORD=secret") == true)
        #expect(request.Env?.contains("POSTGRES_DB=test") == true)
    }

    @Test("Command override is passed through")
    func commandOverride() {
        let config = ContainerConfiguration(
            image: "postgres:16",
            command: ["postgres", "-c", "log_statement=all"]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.Cmd == ["postgres", "-c", "log_statement=all"])
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

        #expect(request.ExposedPorts?["80/tcp"] != nil)
        #expect(request.ExposedPorts?["443/tcp"] != nil)

        let binding80 = request.HostConfig?.PortBindings?["80/tcp"]
        #expect(binding80?.count == 1)
        #expect(binding80?[0].HostPort == "8080")

        // No host port specified → empty string (Docker assigns random port)
        let binding443 = request.HostConfig?.PortBindings?["443/tcp"]
        #expect(binding443?[0].HostPort == "")
    }

    @Test("UDP port uses correct protocol key")
    func udpPort() {
        let config = ContainerConfiguration(
            image: "dns",
            ports: [PortMapping(containerPort: 53, protocol: .udp)]
        )
        let request = runtime.buildCreateRequest(from: config)

        #expect(request.ExposedPorts?["53/udp"] != nil)
        #expect(request.HostConfig?.PortBindings?["53/udp"] != nil)
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

        let binds = request.HostConfig?.Binds
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

        #expect(request.Healthcheck?.Test == ["CMD", "curl", "-f", "http://localhost/"])
        #expect(request.Healthcheck?.Interval == 10_000_000_000)
        #expect(request.Healthcheck?.Timeout == 5_000_000_000)
        #expect(request.Healthcheck?.Retries == 3)
        #expect(request.Healthcheck?.StartPeriod == 2_000_000_000)
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

        #expect(decoded.Image == "app:v2")
        #expect(decoded.Cmd == ["serve", "--port", "8080"])
        #expect(decoded.Env == ["FOO=bar"])
        #expect(decoded.ExposedPorts?["8080/tcp"] != nil)
        #expect(decoded.HostConfig?.PortBindings?["8080/tcp"]?[0].HostPort == "9090")
        #expect(decoded.HostConfig?.Binds == ["/tmp:/data"])
    }
}
