import LocalContainers

/// Helpers for constructing AWS endpoint URLs pointing at a LocalStack container.
public struct LocalStackEndpoint: Sendable {
    /// Public DNS name LocalStack maintains as an A record pointing at
    /// 127.0.0.1. Connecting via this hostname allows TLS to validate
    /// against LocalStack's public certificate, which is issued for this
    /// domain. Required by `cdklocal` and other AWS tooling that constructs
    /// service URLs relative to this hostname.
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

    /// HTTPS endpoint URL suitable for passing to AWS SDK configuration or CLI
    /// from the **host** (test runner). Uses the ``localstackHostname`` so TLS
    /// validates against LocalStack's public certificate and `cdklocal`/etc.
    /// can construct asset URLs.
    ///
    /// Not usable from sibling containers — `localstackHostname` resolves to
    /// 127.0.0.1, which inside a sibling container is the sibling itself, not
    /// LocalStack. For cross-container env injection use
    /// ``awsEndpointForSiblings()`` instead.
    public func awsEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        return "https://\(Self.localstackHostname):\(hostPort)"
    }

    /// Endpoint URL usable from sibling containers on the same Docker bridge —
    /// HTTP + the LocalStack container's bridge gateway IP + the mapped host
    /// port. The gateway IP is reachable both from the host (it's the host's
    /// bridge interface) and from sibling containers (it's their default route
    /// to the host), making this URL the right choice for env injection into a
    /// ``@DockerfileContainer`` sibling.
    ///
    /// This drops TLS validation in favor of cross-container reachability —
    /// the trade-off worth making for tests, since LocalStack's cert is just
    /// a stand-in. Falls back to ``gatewayEndpoint()`` when the runtime
    /// doesn't expose a bridge gateway (which would be reachable from the
    /// host but not from siblings — caller should expect failures in that
    /// case).
    public func awsEndpointForSiblings() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        let host = container.bridgeGateway ?? container.host
        return "http://\(host):\(hostPort)"
    }

    /// Endpoint URL for a specific AWS service. Same as ``awsEndpoint()``
    /// — LocalStack routes all services through the gateway.
    public func endpoint(for service: String) throws -> String {
        try awsEndpoint()
    }
}
