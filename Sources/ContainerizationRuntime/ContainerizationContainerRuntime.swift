import Containerization
import LocalContainers
import Logging

/// ``ContainerRuntime`` implementation backed by Apple's Containerization framework.
///
/// Available on macOS 26+ with Apple Silicon. Each container runs as a
/// lightweight Linux VM with its own IP address via ``VmnetNetwork``.
public struct ContainerizationContainerRuntime: ContainerRuntime {
    private let manager: ContainerizationManager

    public init() {
        self.manager = ContainerizationManager()
    }

    public func pullImage(_ reference: String) async throws {
        try await manager.pullImage(reference)
    }

    public func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> RunningContainer {
        guard #available(macOS 26.0, *) else {
            throw ContainerError.runtimeError(
                "ContainerizationContainerRuntime requires macOS 26.0 or later"
            )
        }
        let result = try await manager.startContainer(from: configuration)
        return RunningContainer(
            id: result.containerID,
            name: result.name,
            image: configuration.image,
            host: result.host,
            ports: result.ports
        )
    }

    public func stopContainer(_ container: RunningContainer) async throws {
        try await manager.stopContainer(identifier: container.id)
    }

    public func removeContainer(_ container: RunningContainer) async throws {
        try await manager.removeContainer(identifier: container.id)
    }

    public func exec(
        command: [String],
        in container: RunningContainer
    ) async throws -> Int32 {
        try await manager.execCommand(command, containerID: container.id)
    }

    public func inspect(
        container: RunningContainer
    ) async throws -> ContainerInspection {
        await manager.inspect(containerID: container.id)
    }

    public func logs(for container: RunningContainer) async throws -> String {
        try await manager.logs(containerID: container.id)
    }
}
