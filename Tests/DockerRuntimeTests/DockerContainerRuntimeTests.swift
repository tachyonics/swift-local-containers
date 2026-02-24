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

    @Test("mapInspection maps healthy status")
    func mapInspectionHealthy() {
        let response = InspectContainerResponse(
            id: "c1",
            name: "test",
            state: .init(
                status: "running",
                running: true,
                health: .init(status: "healthy")
            ),
            networkSettings: .init()
        )
        let result = runtime.mapInspection(response)
        #expect(result.isRunning == true)
        #expect(result.healthStatus == .healthy)
    }

    @Test("mapInspection maps unhealthy status")
    func mapInspectionUnhealthy() {
        let response = InspectContainerResponse(
            id: "c2",
            name: "test",
            state: .init(
                status: "running",
                running: true,
                health: .init(status: "unhealthy")
            ),
            networkSettings: .init()
        )
        let result = runtime.mapInspection(response)
        #expect(result.healthStatus == .unhealthy)
    }

    @Test("mapInspection maps starting status")
    func mapInspectionStarting() {
        let response = InspectContainerResponse(
            id: "c3",
            name: "test",
            state: .init(
                status: "running",
                running: true,
                health: .init(status: "starting")
            ),
            networkSettings: .init()
        )
        let result = runtime.mapInspection(response)
        #expect(result.healthStatus == .starting)
    }

    @Test("mapInspection defaults to notConfigured when no health check")
    func mapInspectionNoHealth() {
        let response = InspectContainerResponse(
            id: "c4",
            name: "test",
            state: .init(status: "running", running: true, health: nil),
            networkSettings: .init()
        )
        let result = runtime.mapInspection(response)
        #expect(result.healthStatus == .notConfigured)
    }

    @Test("mapInspection reflects running state")
    func mapInspectionNotRunning() {
        let response = InspectContainerResponse(
            id: "c5",
            name: "test",
            state: .init(status: "exited", running: false, health: nil),
            networkSettings: .init()
        )
        let result = runtime.mapInspection(response)
        #expect(result.isRunning == false)
    }

    // MARK: - extractGateway

    @Test("extractGateway prefers top-level gateway when populated")
    func extractGatewayTopLevel() {
        let settings = InspectContainerResponse.NetworkSettings(
            gateway: "10.0.0.1",
            networks: ["bridge": .init(gateway: "172.17.0.1")]
        )
        #expect(runtime.extractGateway(from: settings) == "10.0.0.1")
    }

    @Test("extractGateway falls back to Networks map when top-level is empty")
    func extractGatewayFromNetworks() {
        let settings = InspectContainerResponse.NetworkSettings(
            gateway: "",
            networks: ["bridge": .init(gateway: "172.17.0.1")]
        )
        #expect(runtime.extractGateway(from: settings) == "172.17.0.1")
    }

    @Test("extractGateway falls back to Networks map when top-level is nil")
    func extractGatewayFromNetworksNilTopLevel() {
        let settings = InspectContainerResponse.NetworkSettings(
            gateway: nil,
            networks: ["bridge": .init(gateway: "172.18.0.1")]
        )
        #expect(runtime.extractGateway(from: settings) == "172.18.0.1")
    }

    @Test("extractGateway returns nil when no gateway available")
    func extractGatewayNone() {
        let settings = InspectContainerResponse.NetworkSettings(
            gateway: "",
            networks: [:]
        )
        #expect(runtime.extractGateway(from: settings) == nil)
    }

    @Test("extractGateway skips networks with empty gateway")
    func extractGatewaySkipsEmpty() {
        let settings = InspectContainerResponse.NetworkSettings(
            gateway: nil,
            networks: [
                "none": .init(gateway: ""),
                "bridge": .init(gateway: "172.17.0.1"),
            ]
        )
        #expect(runtime.extractGateway(from: settings) == "172.17.0.1")
    }

    // MARK: - resolveHost

    @Test("resolveHost uses gateway when inside Docker, 127.0.0.1 otherwise")
    func resolveHostWithGateway() {
        let host = runtime.resolveHost(gateway: "172.17.0.1")
        let inDocker = FileManager.default.fileExists(atPath: "/.dockerenv")
        if inDocker {
            #expect(host == "172.17.0.1")
        } else {
            #expect(host == "127.0.0.1")
        }
    }

    @Test("resolveHost returns 127.0.0.1 when gateway is nil")
    func resolveHostNilGateway() {
        #expect(runtime.resolveHost(gateway: nil) == "127.0.0.1")
    }

    @Test("resolveHost returns 127.0.0.1 when gateway is empty")
    func resolveHostEmptyGateway() {
        #expect(runtime.resolveHost(gateway: "") == "127.0.0.1")
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
