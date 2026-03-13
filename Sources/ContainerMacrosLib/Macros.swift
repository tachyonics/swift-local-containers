@_exported import ContainerTestSupport
@_exported import LocalContainers
@_exported import LocalStack

/// Scans properties for `@Container` / `@LocalStackContainer` attributes and
/// generates `ContainerKey` enums and a `containerTrait` static property.
@attached(member, names: arbitrary)
public macro ContainerSuite() =
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
