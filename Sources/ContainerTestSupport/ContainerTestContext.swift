import LocalContainers

/// Provides type-safe access to running containers within a test scope.
///
/// Access the current context via ``ContainerTestContext/current``.
/// Use the type-safe subscript to retrieve a container by its ``ContainerKey`` type.
public struct ContainerTestContext: Sendable {
    /// The current container context, set by ``ContainerTrait`` during test execution.
    @TaskLocal public static var current: ContainerTestContext?

    private let containers: [ObjectIdentifier: RunningContainer]
    private let stackOutputs: [ObjectIdentifier: [String: String]]
    private let typedOutputs: [ObjectIdentifier: any Sendable]

    init(
        containers: [ObjectIdentifier: RunningContainer],
        stackOutputs: [ObjectIdentifier: [String: String]] = [:],
        typedOutputs: [ObjectIdentifier: any Sendable] = [:]
    ) {
        self.containers = containers
        self.stackOutputs = stackOutputs
        self.typedOutputs = typedOutputs
    }

    /// Look up a running container by its ``ContainerKey`` type.
    ///
    /// - Throws: ``ContainerError/containerNotFound(id:)`` if no container
    ///   was started for the given key.
    public subscript<K: ContainerKey>(_ key: K.Type) -> RunningContainer {
        get throws {
            try container(for: ObjectIdentifier(key))
        }
    }

    /// Look up a running container by its erased key identifier.
    ///
    /// - Throws: ``ContainerError/containerNotFound(id:)`` if no container
    ///   was started for the given key.
    public func container(for keyID: ObjectIdentifier) throws -> RunningContainer {
        guard let container = containers[keyID] else {
            throw ContainerError.containerNotFound(id: String(describing: keyID))
        }
        return container
    }

    /// Look up raw CloudFormation stack outputs for a given key identifier.
    public func outputs(for keyID: ObjectIdentifier) -> [String: String]? {
        stackOutputs[keyID]
    }

    /// Look up a pre-constructed typed output for a given key identifier.
    ///
    /// Used by macro-generated accessors to retrieve ``StackOutputs`` values.
    public func output<T: Sendable>(for keyID: ObjectIdentifier) -> T? {
        typedOutputs[keyID] as? T
    }

    /// Returns the current context or throws if none is set.
    ///
    /// Convenience for macro-generated code that needs a non-optional context.
    public static func requireCurrent() throws -> ContainerTestContext {
        guard let ctx = current else {
            throw ContainerError.runtimeError(
                "No ContainerTestContext is active — are you inside a @Suite(.containers(...)) scope?"
            )
        }
        return ctx
    }
}
