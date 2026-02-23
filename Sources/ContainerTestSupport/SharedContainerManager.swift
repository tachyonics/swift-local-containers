import Dispatch
import Foundation
import LocalContainers
import Logging
import PlatformRuntime

/// Manages singleton containers that persist across the entire test process.
///
/// Use this for expensive container setups (e.g. LocalStack + large
/// CloudFormation templates) where per-suite startup would be too slow.
/// The first access starts the container; subsequent accesses reuse it.
/// Containers are cleaned up at process exit.
public actor SharedContainerManager {
    /// The shared singleton instance.
    public static let shared = SharedContainerManager()

    private var containers: [ObjectIdentifier: RunningContainer] = [:]
    private var runtime: (any ContainerRuntime)?
    private let logger = Logger(label: "SharedContainerManager")
    private var cleanupRegistered = false

    private init() {}

    /// Get or start a container for the given key.
    public func container<K: ContainerKey>(
        for key: K.Type,
        runtime: any ContainerRuntime = PlatformRuntime()
    ) async throws -> RunningContainer {
        let id = ObjectIdentifier(key)

        if let existing = containers[id] {
            return existing
        }

        registerCleanupIfNeeded(runtime: runtime)

        let spec = key.spec
        logger.info("Starting shared container", metadata: ["key": "\(key)", "image": "\(spec.configuration.image)"])

        try await runtime.pullImage(spec.configuration.image)
        let container = try await runtime.startContainer(from: spec.configuration)

        // Wait for container readiness
        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: spec.configuration,
            runtime: runtime
        )

        // Run setup steps
        for setup in spec.setups {
            try await setup.setUp(container: container)
        }

        containers[id] = container
        return container
    }

    /// Resolve containers for multiple keys, returning a ``ContainerTestContext``.
    public func context(
        for keys: [any ContainerKey.Type],
        runtime: any ContainerRuntime = PlatformRuntime()
    ) async throws -> ContainerTestContext {
        var resolved: [ObjectIdentifier: RunningContainer] = [:]
        for key in keys {
            let id = ObjectIdentifier(key)
            let container = try await container(for: key, runtime: runtime)
            resolved[id] = container
        }
        return ContainerTestContext(containers: resolved)
    }

    /// Stop and remove all shared containers.
    public func shutdownAll() async {
        guard let runtime else { return }

        for (_, container) in containers {
            do {
                try await runtime.stopContainer(container)
                try await runtime.removeContainer(container)
            } catch {
                logger.warning(
                    "Failed to clean up container",
                    metadata: [
                        "id": "\(container.id)",
                        "error": "\(error)",
                    ]
                )
            }
        }
        containers.removeAll()
    }

    private func registerCleanupIfNeeded(runtime: any ContainerRuntime) {
        guard !cleanupRegistered else { return }
        self.runtime = runtime
        cleanupRegistered = true

        // Register atexit cleanup. Since atexit is synchronous, we use
        // a detached task that blocks briefly to allow cleanup.
        atexit {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await SharedContainerManager.shared.shutdownAll()
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}
