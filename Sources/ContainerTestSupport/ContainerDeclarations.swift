import LocalContainers

/// A type that provides a ``ContainerTrait`` for use with `@Suite`.
///
/// Conformance is generated automatically by the `@Containers` macro,
/// allowing `@Suite` to resolve `containerTrait` through the protocol
/// requirement before the macro expands:
///
/// ```swift
/// @Containers
/// enum MyContainers {
///     @Container(image: "postgres:16", ports: [5432])
///     static var db: RunningContainer
/// }
///
/// @Suite(MyContainers.containerTrait, .tags(.integration))
/// struct MyTests { ... }
/// ```
public protocol ContainerDeclarations: Sendable {
    associatedtype Runtime: ContainerRuntime
    static var containerTrait: ContainerTrait<Runtime> { get }
}
