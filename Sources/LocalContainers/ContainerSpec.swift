/// Bundles a container configuration with its post-startup setup steps.
public struct ContainerSpec: Sendable {
    /// The container configuration.
    public let configuration: ContainerConfiguration

    /// Setup steps to run after the container is started and healthy.
    public let setups: [any ContainerSetup]

    public init(
        _ configuration: ContainerConfiguration,
        setups: [any ContainerSetup] = []
    ) {
        self.configuration = configuration
        self.setups = setups
    }
}
