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
        try await client.startContainer(id: response.Id)

        // Inspect to get resolved ports
        let inspection = try await client.inspectContainer(id: response.Id)
        let resolvedPorts = DockerPortResolver.resolve(from: inspection.NetworkSettings)

        return RunningContainer(
            id: response.Id,
            name: inspection.Name,
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

    // MARK: - Private

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
                HostIp: "0.0.0.0",
                HostPort: mapping.hostPort.map(String.init) ?? ""
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
                Test: hc.test,
                Interval: Int(hc.interval.components.seconds) * 1_000_000_000,
                Timeout: Int(hc.timeout.components.seconds) * 1_000_000_000,
                Retries: hc.retries,
                StartPeriod: Int(hc.startPeriod.components.seconds) * 1_000_000_000
            )
        }

        return CreateContainerRequest(
            Image: config.image,
            Env: env.isEmpty ? nil : env,
            Cmd: config.command,
            ExposedPorts: exposedPorts.isEmpty ? nil : exposedPorts,
            HostConfig: HostConfig(
                PortBindings: portBindings.isEmpty ? nil : portBindings,
                Binds: binds.isEmpty ? nil : binds
            ),
            Healthcheck: healthcheck
        )
    }
}
