/// A snapshot of a container's inspection state from the runtime.
public struct ContainerInspection: Sendable {
    /// Whether the container is currently running.
    public let isRunning: Bool

    /// The container's health check status.
    public let healthStatus: HealthStatus

    public init(isRunning: Bool, healthStatus: HealthStatus) {
        self.isRunning = isRunning
        self.healthStatus = healthStatus
    }
}

/// The health status of a container as reported by the runtime.
public enum HealthStatus: String, Sendable {
    /// The container's health check is passing.
    case healthy

    /// The container's health check is failing.
    case unhealthy

    /// The container's health check is still initializing.
    case starting

    /// The container does not have a health check configured.
    case notConfigured
}
