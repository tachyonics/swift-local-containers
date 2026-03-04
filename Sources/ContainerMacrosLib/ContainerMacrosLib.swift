@_exported import ContainerTestSupport
@_exported import LocalContainers
@_exported import LocalStack

/// Generates container keys, a concrete `SuiteTrait` implementation, and a
/// `containerTrait` static property for the annotated struct.
///
/// Usage:
/// ```swift
/// @ContainerSuite
/// @Suite(MyTests.containerTrait, .enabled(if: dockerAvailable))
/// struct MyTests {
///     @Container(image: "postgres:16", ports: [5432])
///     var db: RunningContainer
///
///     @LocalStackContainer(stackName: "test-stack")
///     var aws: S3BucketTemplateOutputs
/// }
/// ```
@attached(member, names: named(containerTrait), named(_ContainerTraitImpl), arbitrary)
public macro ContainerSuite() = #externalMacro(module: "ContainerMacros", type: "ContainerSuiteMacro")

/// Transforms a stored property into a computed getter that retrieves
/// the `RunningContainer` from the current `ContainerTestContext`.
///
/// - Parameters:
///   - image: The container image to use (e.g. `"postgres:16"`).
///   - ports: Container ports to expose (e.g. `[5432]`).
///   - environment: Environment variables for the container.
///   - waitStrategy: The wait strategy expression (e.g. `.log("Ready.")`).
@attached(accessor)
public macro Container(
    image: String,
    ports: [UInt16] = [],
    environment: [String: String] = [:],
    waitStrategy: WaitStrategy = .port
) = #externalMacro(module: "ContainerMacros", type: "ContainerMacro")

/// Transforms a stored property into a computed getter that retrieves
/// typed CloudFormation stack outputs from the current `ContainerTestContext`.
///
/// The property's type annotation must conform to ``StackOutputs``. Template
/// and service metadata are read from the type at runtime.
///
/// - Parameters:
///   - stackName: The CloudFormation stack name.
///   - parameters: CloudFormation template parameters.
@attached(accessor)
public macro LocalStackContainer(
    stackName: String,
    parameters: [String: String] = [:]
) = #externalMacro(module: "ContainerMacros", type: "LocalStackContainerMacro")
