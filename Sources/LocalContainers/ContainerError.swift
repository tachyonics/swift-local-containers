/// Errors that can occur during container lifecycle operations.
public enum ContainerError: Error, Sendable, CustomStringConvertible {
    /// The requested image could not be pulled from the registry.
    case imagePullFailed(image: String, reason: String)

    /// The container failed to start.
    case startFailed(reason: String)

    /// The container failed its health check within the configured timeout.
    case healthCheckFailed(reason: String)

    /// A wait strategy condition was not met within the configured timeout.
    case waitStrategyTimedOut(strategy: String, timeout: Duration)

    /// The container exited unexpectedly while waiting for it to become ready.
    case containerExitedDuringWait(exitCode: Int32?)

    /// The requested port mapping was not found on the running container.
    case portNotFound(containerPort: UInt16)

    /// The container runtime encountered an unexpected error.
    case runtimeError(String)

    /// A container setup step failed.
    case setupFailed(step: String, reason: String)

    /// The container was not found (e.g. already removed).
    case containerNotFound(id: String)

    public var description: String {
        switch self {
        case .imagePullFailed(let image, let reason):
            return "Failed to pull image '\(image)': \(reason)"
        case .startFailed(let reason):
            return "Container failed to start: \(reason)"
        case .healthCheckFailed(let reason):
            return "Health check failed: \(reason)"
        case .waitStrategyTimedOut(let strategy, let timeout):
            return "Wait strategy '\(strategy)' timed out after \(timeout)"
        case .containerExitedDuringWait(let exitCode):
            if let exitCode {
                return "Container exited unexpectedly with code \(exitCode)"
            }
            return "Container exited unexpectedly"
        case .portNotFound(let containerPort):
            return "No port mapping found for container port \(containerPort)"
        case .runtimeError(let message):
            return "Container runtime error: \(message)"
        case .setupFailed(let step, let reason):
            return "Setup step '\(step)' failed: \(reason)"
        case .containerNotFound(let id):
            return "Container not found: \(id)"
        }
    }
}
