import LocalContainers
import Logging
import PlatformRuntime
import Testing

/// A test trait that manages container lifecycles for a test suite.
///
/// Apply to a `@Suite` to start containers before the suite's tests run
/// and stop them after all tests complete:
///
/// ```swift
/// @Suite(.containers(MyContainer.self))
/// struct MyTests {
///     @Test func example() async throws {
///         let ctx = try #require(ContainerTestContext.current)
///         let container = try ctx[MyContainer.self]
///     }
/// }
/// ```
public struct ContainerTrait: SuiteTrait, TestScoping {
    public let isRecursive = true
    let keys: [any ContainerKey.Type]
    let runtime: any ContainerRuntime

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing execute: @Sendable () async throws -> Void
    ) async throws {
        // Only scope at suite level, not individual test cases
        guard testCase == nil else {
            try await execute()
            return
        }

        let logger = Logger(label: "ContainerTrait")
        var started: [ObjectIdentifier: RunningContainer] = [:]

        do {
            // Start all containers
            for key in keys {
                let spec = key.spec
                logger.info("Starting container", metadata: ["image": "\(spec.configuration.image)"])
                try await runtime.pullImage(spec.configuration.image)
                let container = try await runtime.startContainer(from: spec.configuration)

                // Run setup steps
                for setup in spec.setups {
                    try await setup.setUp(container: container)
                }

                started[ObjectIdentifier(key)] = container
            }

            // Execute tests with the context available via @TaskLocal
            let context = ContainerTestContext(containers: started)
            try await ContainerTestContext.$current.withValue(context) {
                try await execute()
            }
        } catch {
            logger.error("Container lifecycle error", metadata: ["error": "\(error)"])
            throw error
        }

        // Teardown — run setup teardowns, then stop and remove containers
        for key in keys {
            let id = ObjectIdentifier(key)
            guard let container = started[id] else { continue }

            for setup in key.spec.setups {
                try? await setup.tearDown(container: container)
            }

            do {
                try await runtime.stopContainer(container)
                try await runtime.removeContainer(container)
            } catch {
                logger.warning("Failed to clean up container", metadata: [
                    "id": "\(container.id)",
                    "error": "\(error)",
                ])
            }
        }
    }
}

/// A test trait that uses ``SharedContainerManager`` for process-wide container sharing.
public struct SharedContainerTrait: SuiteTrait, TestScoping {
    public let isRecursive = true
    let keys: [any ContainerKey.Type]
    let runtime: any ContainerRuntime

    public func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing execute: @Sendable () async throws -> Void
    ) async throws {
        guard testCase == nil else {
            try await execute()
            return
        }

        let context = try await SharedContainerManager.shared.context(
            for: keys,
            runtime: runtime
        )
        try await ContainerTestContext.$current.withValue(context) {
            try await execute()
        }
    }
}

// MARK: - Trait Factory Methods

extension Trait where Self == ContainerTrait {
    /// Creates a suite trait that starts the specified containers for the duration
    /// of the suite. Containers are stopped and removed after all tests complete.
    public static func containers(
        _ keys: any ContainerKey.Type...,
        runtime: any ContainerRuntime = PlatformRuntime()
    ) -> ContainerTrait {
        ContainerTrait(keys: keys, runtime: runtime)
    }
}

extension Trait where Self == SharedContainerTrait {
    /// Creates a suite trait that uses shared (process-wide) containers.
    /// The first suite to use a container starts it; subsequent suites reuse it.
    public static func sharedContainers(
        _ keys: any ContainerKey.Type...,
        runtime: any ContainerRuntime = PlatformRuntime()
    ) -> SharedContainerTrait {
        SharedContainerTrait(keys: keys, runtime: runtime)
    }
}
