/// A composable post-startup step that runs after a container is started and healthy.
///
/// Implementations can deploy CloudFormation templates, run database migrations,
/// seed test data, or perform any other initialization.
public protocol ContainerSetup: Sendable {
    /// Perform setup against the running container.
    func setUp(container: RunningContainer) async throws

    /// Perform cleanup before the container is stopped.
    func tearDown(container: RunningContainer) async throws
}

extension ContainerSetup {
    /// Default no-op teardown.
    public func tearDown(container: RunningContainer) async throws {}
}
