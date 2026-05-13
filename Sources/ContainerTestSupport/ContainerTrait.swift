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
public struct ContainerTrait<R: ContainerRuntime>: SuiteTrait, TestScoping {
    public let isRecursive = false
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

        let logger = LocalContainersLogging.makeLogger(label: "ContainerTrait")
        var started: [ObjectIdentifier: RunningContainer] = [:]
        var stackOutputs: [ObjectIdentifier: [String: String]] = [:]
        var typedOutputs: [ObjectIdentifier: any Sendable] = [:]

        do {
            for key in keys {
                try await startAndConfigure(
                    key: key,
                    started: &started,
                    stackOutputs: &stackOutputs,
                    typedOutputs: &typedOutputs,
                    logger: logger
                )
            }

            // Execute tests with the context available via @TaskLocal,
            // running structured log-streaming tasks alongside for any
            // container that opted in via `containerLogLevel`. When the
            // test execution returns, the streamers are cancelled — they
            // also exit naturally once their containers are stopped at
            // teardown.
            let context = ContainerTestContext(
                containers: started,
                stackOutputs: stackOutputs,
                typedOutputs: typedOutputs
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
                for key in keys {
                    guard let container = started[key.id],
                        let level = key.spec.configuration.containerLogLevel,
                        let streaming = runtime as? any LogStreamingRuntime
                    else {
                        continue
                    }
                    group.addTask {
                        await streaming.streamLogs(
                            container: container,
                            level: level
                        )
                    }
                }
                try await ContainerTestContext.$current.withValue(context) {
                    try await execute()
                }
                group.cancelAll()
            }
        } catch {
            logger.error("Container lifecycle error", metadata: ["error": "\(error)"])
            throw error
        }

        await teardown(started: started, logger: logger)
    }

    /// Brings a single container up: resolves dynamic environment from already-
    /// started siblings, prepares the image (build or pull), starts the
    /// container, waits for it to be ready, and runs any setup steps —
    /// collecting their outputs into the typed/raw output maps for downstream
    /// containers' env resolution.
    private func startAndConfigure(
        key: ErasedContainerKey,
        started: inout [ObjectIdentifier: RunningContainer],
        stackOutputs: inout [ObjectIdentifier: [String: String]],
        typedOutputs: inout [ObjectIdentifier: any Sendable],
        logger: Logger
    ) async throws {
        let spec = key.spec
        let mergedEnv = resolveEnvironment(
            for: spec,
            started: started,
            stackOutputs: stackOutputs,
            typedOutputs: typedOutputs
        )
        let preparedConfig = try await prepareImage(
            for: spec.configuration.with(environment: mergedEnv),
            using: runtime,
            logger: logger
        )
        let container = try await runtime.startContainer(from: preparedConfig)

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: spec.configuration,
            runtime: runtime
        )

        for setup in spec.setups {
            try await setup.setUp(container: container)

            if let outputSetup = setup as? OutputProducingSetup {
                let rawOutputs = try await outputSetup.fetchOutputs(from: container)
                stackOutputs[key.id] = rawOutputs
                if let constructor = key.outputConstructor {
                    typedOutputs[key.id] = try constructor(rawOutputs)
                }
            }
        }

        started[key.id] = container
    }

    private func teardown(
        started: [ObjectIdentifier: RunningContainer],
        logger: Logger
    ) async {
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
public struct SharedContainerTrait<R: ContainerRuntime>: SuiteTrait, TestScoping {
    public let isRecursive = false
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
