/// Strategy used to determine when a container is ready to accept connections.
public enum WaitStrategy: Sendable {
    /// Wait until the first exposed port accepts a TCP connection.
    case port

    /// Wait until the container's health check reports healthy.
    case healthCheck

    /// Wait until the container log output contains the given string.
    case log(String)

    /// Wait for a fixed duration after the container starts.
    case fixedDelay(Duration)

    /// Custom wait strategy implemented by the caller.
    case custom(@Sendable (RunningContainer) async throws -> Void)
}
