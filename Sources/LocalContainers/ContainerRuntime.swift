/// A backend capable of pulling images and managing container lifecycles.
///
/// Implementations exist for Docker/Podman (via REST API) and Apple's
/// Containerization framework. User code should generally interact with
/// `PlatformRuntime` rather than a concrete backend directly.
public protocol ContainerRuntime: Sendable {
    /// Pull an OCI image so it is available locally.
    func pullImage(_ reference: String) async throws

    /// Create and start a container from the given configuration.
    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer

    /// Stop a running container.
    func stopContainer(_ container: RunningContainer) async throws

    /// Remove a stopped container and its associated resources.
    func removeContainer(_ container: RunningContainer) async throws

    /// Inspect a running container and return its current state.
    func inspectContainer(_ container: RunningContainer) async throws -> ContainerInspection

    /// Fetch the log output from a container.
    func containerLogs(_ container: RunningContainer) async throws -> String
}
