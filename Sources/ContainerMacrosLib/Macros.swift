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
        type: "ContainerDeclarationsMacro"
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

/// Marks a property as a Dockerfile-based service container, generating an
/// accessor that returns a ``ServiceEndpoint`` resolved from the running
/// container.
///
/// The image is built from a Dockerfile in the local package, started with
/// auto-detected port mappings (one dynamic host port per `EXPOSE`), and
/// probed for readiness using the supplied wait strategy.
///
/// - Parameters:
///   - context: Build context directory, resolved relative to the nearest
///     enclosing `Package.swift`. Defaults to the package root (`.`).
///   - dockerfile: Path to the Dockerfile within the build context.
///     Defaults to `"Dockerfile"`.
///   - waitStrategy: How to determine readiness. Defaults to `.port`.
@attached(accessor)
public macro DockerfileContainer(
    context: String = ".",
    dockerfile: String = "Dockerfile",
    waitStrategy: WaitStrategy = .port
) =
    #externalMacro(
        module: "ContainerMacros",
        type: "DockerfileContainerMacro"
    )
