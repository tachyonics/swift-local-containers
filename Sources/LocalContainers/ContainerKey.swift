/// A type-safe key identifying a container definition.
///
/// Each container definition conforms to `ContainerKey` and provides its
/// ``ContainerSpec``. This enables compiler-checked lookups instead of
/// error-prone string keys.
///
/// ```swift
/// struct MyPostgres: ContainerKey {
///     static let spec = ContainerSpec(
///         ContainerConfiguration(
///             image: "postgres:16",
///             ports: [PortMapping(containerPort: 5432)],
///             environment: ["POSTGRES_PASSWORD": "test"]
///         )
///     )
/// }
/// ```
public protocol ContainerKey: Sendable {
    /// The container specification for this key.
    static var spec: ContainerSpec { get }
}
