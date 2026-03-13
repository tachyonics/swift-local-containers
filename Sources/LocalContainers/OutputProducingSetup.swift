/// A ``ContainerSetup`` that can produce key-value outputs from a running container.
///
/// Used by ``ContainerTrait`` to collect outputs after setup completes,
/// enabling typed output access in macro-generated code.
public protocol OutputProducingSetup: ContainerSetup {
    /// Fetch outputs from the running container after setup has completed.
    func fetchOutputs(from container: RunningContainer) async throws -> [String: String]
}
