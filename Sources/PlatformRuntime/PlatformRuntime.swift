import DockerRuntime
import LocalContainers

#if canImport(ContainerizationRuntime)
import ContainerizationRuntime
#endif

/// A ``ContainerRuntime`` that automatically selects the appropriate backend
/// for the current platform.
///
/// - macOS 26+: Uses ``ContainerizationContainerRuntime`` (Apple Containerization framework)
/// - Linux: Uses ``DockerContainerRuntime`` (Docker/Podman REST API)
///
/// This allows the same test code to run on macOS development machines and
/// Linux CI without any platform-specific configuration.
public struct PlatformRuntime: ContainerRuntime {
    private let underlying: any ContainerRuntime

    /// Creates a `PlatformRuntime` using the default backend for the current platform.
    public init() {
        #if canImport(ContainerizationRuntime)
        self.underlying = ContainerizationContainerRuntime()
        #else
        self.underlying = DockerContainerRuntime()
        #endif
    }

    /// Creates a `PlatformRuntime` with an explicit runtime backend.
    public init(runtime: any ContainerRuntime) {
        self.underlying = runtime
    }

    public func pullImage(_ reference: String) async throws {
        try await underlying.pullImage(reference)
    }

    public func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> RunningContainer {
        try await underlying.startContainer(from: configuration)
    }

    public func stopContainer(_ container: RunningContainer) async throws {
        try await underlying.stopContainer(container)
    }

    public func removeContainer(_ container: RunningContainer) async throws {
        try await underlying.removeContainer(container)
    }
}
