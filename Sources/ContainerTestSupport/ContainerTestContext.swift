import LocalContainers

/// Provides type-safe access to running containers within a test scope.
///
/// Access the current context via ``ContainerTestContext/current``.
/// Use the type-safe subscript to retrieve a container by its ``ContainerKey`` type.
public struct ContainerTestContext: Sendable {
    /// The current container context, set by ``ContainerTrait`` during test execution.
    @TaskLocal public static var current: ContainerTestContext?

    private let containers: [ObjectIdentifier: RunningContainer]

    init(containers: [ObjectIdentifier: RunningContainer]) {
        self.containers = containers
    }

    /// Look up a running container by its ``ContainerKey`` type.
    ///
    /// - Throws: ``ContainerError/containerNotFound(id:)`` if no container
    ///   was started for the given key.
    public subscript<K: ContainerKey>(_ key: K.Type) -> RunningContainer {
        get throws {
            let id = ObjectIdentifier(key)
            guard let container = containers[id] else {
                throw ContainerError.containerNotFound(id: String(describing: key))
            }
            return container
        }
    }
}
