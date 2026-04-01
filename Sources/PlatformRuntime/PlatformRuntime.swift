import DockerRuntime
import LocalContainers

#if canImport(ContainerizationRuntime)
import ContainerizationRuntime
#endif

/// A ``ContainerRuntime`` that automatically selects the appropriate backend
/// for the current platform.
///
/// By default, ``DockerContainerRuntime`` is used on all platforms. On macOS,
/// the experimental Apple Containerization backend can be enabled by activating
/// the `Containerization` package trait:
///
/// ```swift
/// .package(url: "…/swift-local-containers.git", from: "…",
///          traits: ["Containerization"])
/// ```
///
/// or via the command line:
///
/// ```
/// swift build --traits Containerization
/// ```
public struct PlatformRuntime: ContainerRuntime {
    #if canImport(ContainerizationRuntime)
    private let underlying: ContainerizationContainerRuntime
    #else
    private let underlying: DockerContainerRuntime
    #endif

    /// Creates a `PlatformRuntime` using the default backend for the current platform.
    public init() {
        #if canImport(ContainerizationRuntime)
        self.underlying = ContainerizationContainerRuntime()
        #else
        self.underlying = DockerContainerRuntime()
        #endif
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

    public func exec(command: [String], in container: RunningContainer) async throws -> Int32 {
        try await underlying.exec(command: command, in: container)
    }

    public func inspect(container: RunningContainer) async throws -> ContainerInspection {
        try await underlying.inspect(container: container)
    }

    public func logs(for container: RunningContainer) async throws -> String {
        try await underlying.logs(for: container)
    }
}
