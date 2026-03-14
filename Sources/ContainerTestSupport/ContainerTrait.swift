import LocalContainers
import Logging
import PlatformRuntime
import Testing

/// A test trait that manages container lifecycles for a test suite.
///
/// Generic over the runtime to avoid storing `any ContainerRuntime` as an
/// existential.
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
// Also conforms to TestTrait to work around a Swift Testing bug where
// _recursivelyApplyTraits inserts suite traits into child test nodes,
// triggering a precondition that all traits on non-suite tests are TestTrait.
public struct ContainerTrait<R: ContainerRuntime>: SuiteTrait, TestTrait, TestScoping {
    public let isRecursive = true
    let keys: [ErasedContainerKey]
    let runtime: R

    public init(keys: [ErasedContainerKey], runtime: R) {
        self.keys = keys
        self.runtime = runtime
    }

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
        var stackOutputs: [ObjectIdentifier: [String: String]] = [:]
        var typedOutputs: [ObjectIdentifier: any Sendable] = [:]

        do {
            // Start all containers
            for key in keys {
                let spec = key.spec
                logger.info("Starting container", metadata: ["image": "\(spec.configuration.image)"])
                try await runtime.pullImage(spec.configuration.image)
                let container = try await runtime.startContainer(from: spec.configuration)

                // Wait for container readiness
                try await WaitStrategyExecutor.waitUntilReady(
                    container: container,
                    configuration: spec.configuration,
                    runtime: runtime
                )

                // Run setup steps and collect outputs
                for setup in spec.setups {
                    try await setup.setUp(container: container)

                    if let outputSetup = setup as? OutputProducingSetup {
                        let rawOutputs = try await outputSetup.fetchOutputs(
                            from: container
                        )
                        stackOutputs[key.id] = rawOutputs

                        if let constructor = key.outputConstructor {
                            typedOutputs[key.id] = try constructor(rawOutputs)
                        }
                    }
                }

                started[key.id] = container
            }

            // Execute tests with the context available via @TaskLocal
            let context = ContainerTestContext(
                containers: started,
                stackOutputs: stackOutputs,
                typedOutputs: typedOutputs
            )
            try await ContainerTestContext.$current.withValue(context) {
                try await execute()
            }
        } catch {
            logger.error("Container lifecycle error", metadata: ["error": "\(error)"])
            throw error
        }

        // Teardown — run setup teardowns, then stop and remove containers
        for key in keys {
            guard let container = started[key.id] else { continue }

            for setup in key.spec.setups {
                try? await setup.tearDown(container: container)
            }

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
    }
}

/// A test trait that uses ``SharedContainerManager`` for process-wide container sharing.
///
/// Generic over the runtime for the same reason as ``ContainerTrait``.
// Also conforms to TestTrait — see ContainerTrait comment above.
public struct SharedContainerTrait<R: ContainerRuntime>: SuiteTrait, TestTrait, TestScoping {
    public let isRecursive = true
    let keys: [ErasedContainerKey]
    let runtime: R

    public init(keys: [ErasedContainerKey], runtime: R) {
        self.keys = keys
        self.runtime = runtime
    }

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

extension SuiteTrait {
    /// Creates a suite trait that starts the specified containers for the duration
    /// of the suite. Containers are stopped and removed after all tests complete.
    public static func containers(
        _ keys: any ContainerKey.Type...,
        runtime: some ContainerRuntime = PlatformRuntime()
    ) -> ContainerTrait<some ContainerRuntime> {
        ContainerTrait(keys: keys.map { ErasedContainerKey($0) }, runtime: runtime)
    }

    /// Creates a suite trait that uses shared (process-wide) containers.
    /// The first suite to use a container starts it; subsequent suites reuse it.
    public static func sharedContainers(
        _ keys: any ContainerKey.Type...,
        runtime: some ContainerRuntime = PlatformRuntime()
    ) -> SharedContainerTrait<some ContainerRuntime> {
        SharedContainerTrait(keys: keys.map { ErasedContainerKey($0) }, runtime: runtime)
    }
}
