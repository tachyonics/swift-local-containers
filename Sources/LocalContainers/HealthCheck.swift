/// Configuration for a container health check.
public struct HealthCheckConfig: Sendable {
    /// The command to run inside the container to check health.
    public let test: [String]

    /// Time between health check attempts.
    public let interval: Duration

    /// Maximum time to wait for a single health check to complete.
    public let timeout: Duration

    /// Number of consecutive failures before the container is considered unhealthy.
    public let retries: Int

    /// Grace period after container start before health checks begin.
    public let startPeriod: Duration

    public init(
        test: [String],
        interval: Duration = .seconds(10),
        timeout: Duration = .seconds(5),
        retries: Int = 3,
        startPeriod: Duration = .seconds(0)
    ) {
        self.test = test
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.startPeriod = startPeriod
    }
}
