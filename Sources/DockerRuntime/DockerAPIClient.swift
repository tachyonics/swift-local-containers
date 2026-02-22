import AsyncHTTPClient
import LocalContainers
import Logging

/// HTTP client for the Docker Engine API over a Unix domain socket.
///
/// This is currently a stub — method bodies will be filled in when the
/// Docker runtime integration is implemented.
public struct DockerAPIClient: Sendable {
    private let socketPath: String
    private let logger: Logger

    /// Creates a client connecting to the Docker daemon at the given Unix socket.
    ///
    /// - Parameter socketPath: Path to the Docker socket. Defaults to `/var/run/docker.sock`.
    public init(
        socketPath: String = "/var/run/docker.sock",
        logger: Logger = Logger(label: "DockerAPIClient")
    ) {
        self.socketPath = socketPath
        self.logger = logger
    }

    /// Pull an image by reference.
    public func pullImage(_ reference: String) async throws {
        logger.info("Pulling image", metadata: ["image": "\(reference)"])
        // TODO: POST /images/create?fromImage=<reference>
        throw ContainerError.runtimeError("DockerAPIClient.pullImage not yet implemented")
    }

    /// Create a container from the given request body.
    public func createContainer(
        _ request: CreateContainerRequest,
        name: String? = nil
    ) async throws -> CreateContainerResponse {
        logger.info("Creating container", metadata: ["image": "\(request.image)"])
        // TODO: POST /containers/create
        throw ContainerError.runtimeError("DockerAPIClient.createContainer not yet implemented")
    }

    /// Start a created container.
    public func startContainer(id: String) async throws {
        logger.info("Starting container", metadata: ["id": "\(id)"])
        // TODO: POST /containers/{id}/start
        throw ContainerError.runtimeError("DockerAPIClient.startContainer not yet implemented")
    }

    /// Inspect a running container.
    public func inspectContainer(id: String) async throws -> InspectContainerResponse {
        logger.info("Inspecting container", metadata: ["id": "\(id)"])
        // TODO: GET /containers/{id}/json
        throw ContainerError.runtimeError("DockerAPIClient.inspectContainer not yet implemented")
    }

    /// Stop a running container.
    public func stopContainer(id: String, timeout: Int = 10) async throws {
        logger.info("Stopping container", metadata: ["id": "\(id)"])
        // TODO: POST /containers/{id}/stop
        throw ContainerError.runtimeError("DockerAPIClient.stopContainer not yet implemented")
    }

    /// Remove a container.
    public func removeContainer(id: String, force: Bool = false) async throws {
        logger.info("Removing container", metadata: ["id": "\(id)"])
        // TODO: DELETE /containers/{id}
        throw ContainerError.runtimeError("DockerAPIClient.removeContainer not yet implemented")
    }
}
