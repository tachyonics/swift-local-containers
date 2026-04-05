import LocalContainers

/// Helpers for constructing AWS endpoint URLs pointing at a LocalStack container.
public struct LocalStackEndpoint: Sendable {
    /// Public DNS name LocalStack maintains as an A record pointing at
    /// 127.0.0.1. Connecting via this hostname allows TLS to validate
    /// against LocalStack's public certificate, which is issued for this
    /// domain.
    public static let localstackHostname = "localhost.localstack.cloud"

    private let container: RunningContainer
    private let gatewayPort: UInt16

    public init(container: RunningContainer, gatewayPort: UInt16 = 4566) {
        self.container = container
        self.gatewayPort = gatewayPort
    }

    /// Raw HTTP gateway endpoint URL (e.g. `http://127.0.0.1:49152`).
    /// Use for raw HTTP clients; AWS SDK clients should prefer
    /// ``awsEndpoint()``.
    public func gatewayEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        return "http://\(container.host):\(hostPort)"
    }

    /// HTTPS endpoint URL suitable for passing to AWS SDK configuration or CLI.
    /// Uses the ``localstackHostname`` so TLS validates against LocalStack's
    /// public certificate. LocalStack routes all services through the gateway.
    public func awsEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        return "https://\(Self.localstackHostname):\(hostPort)"
    }

    /// Endpoint URL for a specific AWS service. Same as ``awsEndpoint()``
    /// — LocalStack routes all services through the gateway.
    public func endpoint(for service: String) throws -> String {
        try awsEndpoint()
    }
}
