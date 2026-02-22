import Containerization
import LocalContainers
import Logging

/// ``ContainerRuntime`` implementation backed by Apple's Containerization framework.
///
/// Available on macOS 26+ with Apple Silicon. This is currently a stub —
/// the full implementation will manage lightweight Linux VMs via
/// the Containerization framework.
public struct ContainerizationContainerRuntime: ContainerRuntime {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "ContainerizationContainerRuntime")) {
        self.logger = logger
    }

    public func pullImage(_ reference: String) async throws {
        logger.info("Pulling image via Containerization", metadata: ["image": "\(reference)"])
        // TODO: Use Containerization.Image to pull OCI images
        throw ContainerError.runtimeError(
            "ContainerizationContainerRuntime.pullImage not yet implemented"
        )
    }

    public func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> RunningContainer {
        logger.info(
            "Starting container via Containerization",
            metadata: ["image": "\(configuration.image)"]
        )
        // TODO: Create and start a VM with the container image
        throw ContainerError.runtimeError(
            "ContainerizationContainerRuntime.startContainer not yet implemented"
        )
    }

    public func stopContainer(_ container: RunningContainer) async throws {
        logger.info("Stopping container via Containerization", metadata: ["id": "\(container.id)"])
        // TODO: Stop the VM
        throw ContainerError.runtimeError(
            "ContainerizationContainerRuntime.stopContainer not yet implemented"
        )
    }

    public func removeContainer(_ container: RunningContainer) async throws {
        logger.info(
            "Removing container via Containerization",
            metadata: ["id": "\(container.id)"]
        )
        // TODO: Remove the VM and its resources
        throw ContainerError.runtimeError(
            "ContainerizationContainerRuntime.removeContainer not yet implemented"
        )
    }
}
