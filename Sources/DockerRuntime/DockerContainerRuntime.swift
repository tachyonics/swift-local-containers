import LocalContainers
import Logging

/// ``ContainerRuntime`` implementation backed by the Docker Engine REST API.
///
/// Uses ``DockerAPIClient`` to communicate with the Docker daemon over a Unix
/// domain socket. Works with Docker and Podman.
public struct DockerContainerRuntime: ContainerRuntime {
    private let client: DockerAPIClient
    private let logger: Logger

    public init(
        socketPath: String = "/var/run/docker.sock",
        logger: Logger = Logger(label: "DockerContainerRuntime")
    ) {
        self.client = DockerAPIClient(socketPath: socketPath, logger: logger)
        self.logger = logger
    }

    public func pullImage(_ reference: String) async throws {
        try await client.pullImage(reference)
    }

    public func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> RunningContainer {
        logger.info("Starting container", metadata: ["image": "\(configuration.image)"])

        // Build the Docker create request from the configuration
        let request = buildCreateRequest(from: configuration)
        let response = try await client.createContainer(request, name: configuration.name)

        // Start the container
        try await client.startContainer(id: response.id)

        // Inspect to get resolved ports
        let inspection = try await client.inspectContainer(id: response.id)
        let resolvedPorts = DockerPortResolver.resolve(from: inspection.networkSettings)

        return RunningContainer(
            id: response.id,
            name: inspection.name,
            image: configuration.image,
            host: "127.0.0.1",
            ports: resolvedPorts
        )
    }

    public func stopContainer(_ container: RunningContainer) async throws {
        try await client.stopContainer(id: container.id)
    }

    public func removeContainer(_ container: RunningContainer) async throws {
        try await client.removeContainer(id: container.id, force: true)
    }

    public func inspectContainer(_ container: RunningContainer) async throws -> ContainerInspection {
        let response = try await client.inspectContainer(id: container.id)
        let healthStatus: HealthStatus = switch response.state.health?.status {
        case "healthy": .healthy
        case "unhealthy": .unhealthy
        case "starting": .starting
        default: .notConfigured
        }
        return ContainerInspection(isRunning: response.state.running, healthStatus: healthStatus)
    }

    public func containerLogs(_ container: RunningContainer) async throws -> String {
        try await client.containerLogs(id: container.id)
    }

    // MARK: - Internal

    func buildCreateRequest(
        from config: ContainerConfiguration
    ) -> CreateContainerRequest {
        var env: [String] = []
        for (key, value) in config.environment {
            env.append("\(key)=\(value)")
        }

        var exposedPorts: [String: EmptyObject] = [:]
        var portBindings: [String: [PortBinding]] = [:]
        for mapping in config.ports {
            let key = "\(mapping.containerPort)/\(mapping.protocol.rawValue)"
            exposedPorts[key] = EmptyObject()
            let binding = PortBinding(
                hostIp: "0.0.0.0",
                hostPort: mapping.hostPort.map(String.init) ?? ""
            )
            portBindings[key] = [binding]
        }

        var binds: [String] = []
        for vol in config.volumes {
            let bind =
                vol.readOnly
                ? "\(vol.hostPath):\(vol.containerPath):ro"
                : "\(vol.hostPath):\(vol.containerPath)"
            binds.append(bind)
        }

        var healthcheck: Healthcheck?
        if let hc = config.healthCheck {
            healthcheck = Healthcheck(
                test: hc.test,
                interval: Int(hc.interval.components.seconds) * 1_000_000_000,
                timeout: Int(hc.timeout.components.seconds) * 1_000_000_000,
                retries: hc.retries,
                startPeriod: Int(hc.startPeriod.components.seconds) * 1_000_000_000
            )
        }

        return CreateContainerRequest(
            image: config.image,
            env: env.isEmpty ? nil : env,
            cmd: config.command,
            exposedPorts: exposedPorts.isEmpty ? nil : exposedPorts,
            hostConfig: HostConfig(
                portBindings: portBindings.isEmpty ? nil : portBindings,
                binds: binds.isEmpty ? nil : binds
            ),
            healthcheck: healthcheck
        )
    }
}
