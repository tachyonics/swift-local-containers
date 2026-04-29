import Foundation
import LocalContainers
import Logging

/// ``ContainerRuntime`` implementation backed by the Docker Engine REST API.
///
/// Uses ``DockerAPIClient`` to communicate with the Docker daemon over a Unix
/// domain socket. Works with Docker and Podman.
public struct DockerContainerRuntime: ContainerRuntime, ImageBuildingRuntime {
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

    package func buildImage(spec: BuildSpec) async throws {
        try await runDockerBuild(spec: spec, logger: logger)
    }

    package func inspectImage(reference: String) async throws -> ImageInspection {
        try await client.inspectImage(reference: reference)
    }

    public func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> RunningContainer {
        let imageRef = configuration.image.imageReference
        logger.info("Starting container", metadata: ["image": "\(imageRef)"])

        // Build the Docker create request from the configuration
        let request = buildCreateRequest(from: configuration)
        let response = try await client.createContainer(request, name: configuration.name)

        // Start the container
        try await client.startContainer(id: response.id)

        // Inspect to get resolved ports
        let inspection = try await client.inspectContainer(id: response.id)
        let resolvedPorts = DockerPortResolver.resolve(from: inspection.networkSettings)

        let gateway = extractGateway(from: inspection.networkSettings)
        let host = resolveHost(gateway: gateway)

        return RunningContainer(
            id: response.id,
            name: inspection.name,
            image: imageRef,
            host: host,
            ports: resolvedPorts
        )
    }

    public func stopContainer(_ container: RunningContainer) async throws {
        try await client.stopContainer(id: container.id)
    }

    public func removeContainer(_ container: RunningContainer) async throws {
        try await client.removeContainer(id: container.id, force: true)
    }

    public func inspect(container: RunningContainer) async throws -> ContainerInspection {
        let response = try await client.inspectContainer(id: container.id)
        return mapInspection(response)
    }

    /// Maps a Docker inspect response to a ``ContainerInspection``.
    func mapInspection(_ response: InspectContainerResponse) -> ContainerInspection {
        ContainerInspection(
            isRunning: response.state.running,
            status: response.state.status,
            exitCode: response.state.running ? nil : response.state.exitCode
        )
    }

    public func exec(command: [String], in container: RunningContainer) async throws -> Int32 {
        let execId = try await client.createExec(
            containerId: container.id,
            command: command
        )
        try await client.startExec(id: execId)
        let response = try await client.inspectExec(id: execId)
        return response.exitCode
    }

    public func logs(for container: RunningContainer) async throws -> String {
        try await client.containerLogs(id: container.id)
    }

    // MARK: - Internal

    /// Extracts the bridge gateway IP from Docker network settings.
    ///
    /// The top-level `Gateway` field in Docker's inspect response is often empty.
    /// The actual gateway is inside `Networks["bridge"].Gateway` (or whichever
    /// network the container is attached to).
    func extractGateway(
        from networkSettings: InspectContainerResponse.NetworkSettings
    ) -> String? {
        // Prefer the top-level gateway if it's populated
        if let gw = networkSettings.gateway, !gw.isEmpty {
            return gw
        }
        // Fall back to the first non-empty gateway in the Networks map
        if let networks = networkSettings.networks {
            for (_, info) in networks {
                if let gw = info.gateway, !gw.isEmpty {
                    return gw
                }
            }
        }
        return nil
    }

    /// Determines the host address to use for connecting to container ports.
    ///
    /// Prefer the bridge gateway IP whenever Docker provides one. The gateway
    /// is reachable from both the host (it's the host's bridge interface) AND
    /// from sibling containers on the same bridge (it's their default route to
    /// the host). Using a single host value that works in both scenarios is
    /// what makes cross-container env injection — sharing a `LocalStackContainer`
    /// endpoint with a `@DockerfileContainer` sibling — work without
    /// per-deployment workarounds. Falls back to 127.0.0.1 only when no gateway
    /// is available (e.g., custom networks without a bridge gateway, or runtimes
    /// that don't populate it).
    func resolveHost(gateway: String?) -> String {
        if let gateway, !gateway.isEmpty {
            return gateway
        }
        return "127.0.0.1"
    }

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

        return CreateContainerRequest(
            image: config.image.imageReference,
            env: env.isEmpty ? nil : env,
            cmd: config.command,
            exposedPorts: exposedPorts.isEmpty ? nil : exposedPorts,
            hostConfig: HostConfig(
                portBindings: portBindings.isEmpty ? nil : portBindings,
                binds: binds.isEmpty ? nil : binds
            )
        )
    }
}
