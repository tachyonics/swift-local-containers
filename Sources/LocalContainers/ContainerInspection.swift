/// A snapshot of a container's inspection state from the runtime.
public struct ContainerInspection: Sendable {
    /// Whether the container is currently running.
    public let isRunning: Bool

    public init(isRunning: Bool) {
        self.isRunning = isRunning
    }
}
