@_exported import ContainerTestSupport
@_exported import LocalContainers
@_exported import LocalStack
@_exported import PlatformRuntime

/// Scans properties for `@Container` / `@LocalStackContainer` attributes and
/// generates `ContainerKey` enums, a `containerTrait` static property, and
/// ``ContainerDeclarations`` conformance.
///
/// Apply to a struct or enum that declares container properties. The generated
/// `containerTrait` can then be passed to `@Suite(...)`:
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
///
/// Container declarations can be shared across multiple suites:
///
/// ```swift
/// @Suite(SharedContainers.containerTrait)
/// struct SuiteA { ... }
///
/// @Suite(SharedContainers.containerTrait)
/// struct SuiteB { ... }
/// ```
@attached(member, names: arbitrary)
@attached(extension, conformances: ContainerDeclarations)
public macro Containers() =
    #externalMacro(
        module: "ContainerMacros",
        type: "ContainerSuiteMacro"
    )

/// Marks a property as a plain container, generating an accessor that looks up
/// the `RunningContainer` from `ContainerTestContext`.
///
/// - Parameters:
///   - image: The OCI image reference (e.g. `"postgres:16"`).
///   - ports: Container ports to expose.
@attached(accessor)
public macro Container(
    image: String,
    ports: [UInt16]
) =
    #externalMacro(
        module: "ContainerMacros",
        type: "ContainerMacro"
    )

/// Marks a property as a LocalStack container backed by a CloudFormation stack,
/// generating an accessor that looks up typed ``StackOutputs`` from
/// `ContainerTestContext`.
///
/// - Parameter stackName: The CloudFormation stack name.
@attached(accessor)
public macro LocalStackContainer(
    stackName: String = "test-stack"
) =
    #externalMacro(
        module: "ContainerMacros",
        type: "LocalStackContainerMacro"
    )
