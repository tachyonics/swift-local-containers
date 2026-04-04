/// A snapshot of a container's inspection state from the runtime.
public struct ContainerInspection: Sendable {
    /// Whether the container is currently running.
    public let isRunning: Bool

    /// The container's status string (e.g. "running", "exited").
    public let status: String

    /// The exit code of the container's main process, if it has exited.
    public let exitCode: Int32?

    public init(isRunning: Bool, status: String = "unknown", exitCode: Int32? = nil) {
        self.isRunning = isRunning
        self.status = status
        self.exitCode = exitCode
    }
}
