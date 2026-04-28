/// Bundles a container configuration with its post-startup setup steps.
public struct ContainerSpec: Sendable {
    /// The container configuration.
    public let configuration: ContainerConfiguration

    /// Setup steps to run after the container is started and healthy.
    public let setups: [any ContainerSetup]

    /// Optional dynamic environment producer evaluated by the trait
    /// just before the container is started. The trait sets up a partial
    /// `ContainerTestContext` (with siblings started so far) before invoking
    /// this closure, so providers can read sibling outputs through the
    /// usual macro-generated computed properties on the enclosing
    /// `@Containers` struct. The result is merged over
    /// `configuration.environment` (dynamic values win on key collision).
    public let environmentProvider: (@Sendable () -> [String: String])?

    public init(
        _ configuration: ContainerConfiguration,
        setups: [any ContainerSetup] = [],
        environmentProvider: (@Sendable () -> [String: String])? = nil
    ) {
        self.configuration = configuration
        self.setups = setups
        self.environmentProvider = environmentProvider
    }
}
