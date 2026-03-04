/// A type-erased wrapper around a ``ContainerKey`` type.
///
/// Eliminates the need to store existential metatypes (`any ContainerKey.Type`)
/// which crash on Linux due to Swift runtime limitations with existential
/// metatype arrays in test traits.
public struct ErasedContainerKey: Sendable {
    /// The unique identity of the original ``ContainerKey`` type.
    public let id: ObjectIdentifier

    /// The container specification from the original key.
    public let spec: ContainerSpec

    /// A human-readable name of the original key type (for diagnostics).
    public let name: String

    /// Wraps a concrete ``ContainerKey`` type.
    public init<K: ContainerKey>(_ key: K.Type) {
        self.id = ObjectIdentifier(key)
        self.spec = key.spec
        self.name = String(describing: key)
    }
}
