import LocalContainers

/// Helpers for constructing AWS endpoint URLs pointing at a LocalStack container.
public struct LocalStackEndpoint: Sendable {
    private let container: RunningContainer
    private let gatewayPort: UInt16

    public init(container: RunningContainer, gatewayPort: UInt16 = 4566) {
        self.container = container
        self.gatewayPort = gatewayPort
    }

    /// The gateway endpoint URL (e.g. `http://127.0.0.1:4566`).
    public func gatewayEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        return "http://\(container.host):\(hostPort)"
    }

    /// AWS endpoint URL suitable for passing to AWS SDK configuration or CLI.
    /// Same as ``gatewayEndpoint()`` — LocalStack routes all services through the gateway.
    public func awsEndpoint() throws -> String {
        try gatewayEndpoint()
    }

    /// Endpoint URL for a specific AWS service.
    public func endpoint(for service: String) throws -> String {
        try gatewayEndpoint()
    }
}
