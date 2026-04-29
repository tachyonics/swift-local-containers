import LocalContainers

/// Helpers for constructing AWS endpoint URLs pointing at a LocalStack container.
public struct LocalStackEndpoint: Sendable {
    private let container: RunningContainer
    private let gatewayPort: UInt16

    public init(container: RunningContainer, gatewayPort: UInt16 = 4566) {
        self.container = container
        self.gatewayPort = gatewayPort
    }

    /// HTTP gateway endpoint URL (e.g. `http://172.17.0.1:49152`). Suitable
    /// for raw HTTP clients.
    public func gatewayEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        return "http://\(container.host):\(hostPort)"
    }

    /// Endpoint URL suitable for passing to AWS SDK configuration. Equivalent
    /// to ``gatewayEndpoint()`` — same scheme, same host, same port.
    ///
    /// The host value comes from ``RunningContainer/host``, which is the
    /// Docker bridge gateway IP — reachable from both the test runner on the
    /// host and from sibling containers on the same bridge. The same URL
    /// works for direct host-to-LocalStack calls and for cross-container env
    /// injection (e.g. a ``@DockerfileContainer`` reading
    /// ``StackOutputs/awsEndpoint`` via an `environment:` closure).
    public func awsEndpoint() throws -> String {
        try gatewayEndpoint()
    }

    /// Endpoint URL for a specific AWS service. Same as ``awsEndpoint()``
    /// — LocalStack routes all services through the gateway.
    public func endpoint(for service: String) throws -> String {
        try awsEndpoint()
    }
}
