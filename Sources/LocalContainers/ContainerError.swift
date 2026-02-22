/// Errors that can occur during container lifecycle operations.
public enum ContainerError: Error, Sendable {
    /// The requested image could not be pulled from the registry.
    case imagePullFailed(image: String, reason: String)

    /// The container failed to start.
    case startFailed(reason: String)

    /// The container failed its health check within the configured timeout.
    case healthCheckFailed(reason: String)

    /// A wait strategy condition was not met within the configured timeout.
    case waitStrategyTimedOut(strategy: String, timeout: Duration)

    /// The requested port mapping was not found on the running container.
    case portNotFound(containerPort: UInt16)

    /// The container runtime encountered an unexpected error.
    case runtimeError(String)

    /// A container setup step failed.
    case setupFailed(step: String, reason: String)

    /// The container was not found (e.g. already removed).
    case containerNotFound(id: String)
}
