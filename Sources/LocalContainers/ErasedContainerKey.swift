/// A type-erased wrapper around a ``ContainerKey`` type.
///
/// Eliminates the need to store existential metatypes (`any ContainerKey.Type`)
/// which crash on Linux due to Swift runtime limitations with existential
/// metatype arrays in test traits.
///
/// All existential state (including `ContainerSpec.setups`) is boxed behind
/// a class reference so the enclosing struct has a trivial inline layout.
public struct ErasedContainerKey: Sendable {
    /// The unique identity of the original ``ContainerKey`` type.
    public let id: ObjectIdentifier

    /// A human-readable name of the original key type (for diagnostics).
    public let name: String

    private let storage: Storage

    /// The container specification from the original key.
    public var spec: ContainerSpec { storage.spec }

    /// Wraps a concrete ``ContainerKey`` type.
    public init<K: ContainerKey>(_ key: K.Type) {
        self.id = ObjectIdentifier(key)
        self.name = String(describing: key)
        self.storage = Storage(spec: key.spec)
    }
}

extension ErasedContainerKey {
    /// Boxes ``ContainerSpec`` (which contains `[any ContainerSetup]`) behind
    /// a class reference so the enclosing struct carries no inline existentials.
    private final class Storage: @unchecked Sendable {
        let spec: ContainerSpec
        init(spec: ContainerSpec) { self.spec = spec }
    }
}
