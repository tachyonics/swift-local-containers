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

    /// Endpoint URL suitable for passing to AWS SDK configuration or CLI
    /// from the **host** (test runner). The form depends on whether the
    /// runner can reach LocalStack via loopback:
    ///
    /// - Bare-metal runner (`container.host == "127.0.0.1"`): returns
    ///   `https://localhost.localstack.cloud:<host_port>` so TLS validates
    ///   against LocalStack's published cert and `cdklocal`/other
    ///   hostname-pinning tools can construct asset URLs.
    /// - Runner inside a container (``DockerContainerRuntime/resolveHost``
    ///   returned the bridge gateway because `/.dockerenv` exists):
    ///   `localhost.localstack.cloud` resolves to 127.0.0.1, which inside
    ///   the runner is the runner's own loopback — not where LocalStack's
    ///   port is bound. Returns `http://<bridge_gateway>:<host_port>`
    ///   instead, which is reachable from the runner's network namespace.
    ///   `cdklocal` and other hostname-pinning tools don't work in this
    ///   mode — they need a bare-metal runner; the library doesn't paper
    ///   over that constraint.
    ///
    /// Not usable from sibling containers regardless of runner location.
    /// For cross-container env injection use ``awsEndpointForSiblings()``.
    public func awsEndpoint() throws -> String {
        let hostPort = try container.mappedPort(gatewayPort)
        if container.host == "127.0.0.1" {
            return "https://\(Self.localstackHostname):\(hostPort)"
        }
        return "http://\(container.host):\(hostPort)"
    }

    /// Endpoint URL usable from sibling containers on the same Docker bridge —
    /// HTTP + the LocalStack container's own bridge-network IP + its
    /// *internal* gateway port (4566 by default, **not** the published host
    /// port). On a shared bridge network, container IPs are directly routable
    /// between siblings, which is the most portable cross-container path —
    /// the bridge-gateway + host-port alternative is unreliable on Docker
    /// Desktop, where published ports aren't always reachable via the bridge
    /// gateway interface.
    ///
    /// Drops TLS validation in favor of cross-container reachability — fine
    /// for tests, since LocalStack's cert is just a stand-in.
    ///
    /// - Throws: ``ContainerError/portNotFound(containerPort:)`` when the
    ///   runtime can't surface a bridge IP for this container.
    public func awsEndpointForSiblings() throws -> String {
        guard let bridgeIP = container.bridgeIPAddress else {
            throw ContainerError.portNotFound(containerPort: gatewayPort)
        }
        return "http://\(bridgeIP):\(gatewayPort)"
    }

    /// Endpoint URL for a specific AWS service. Same as ``awsEndpoint()``
    /// — LocalStack routes all services through the gateway.
    public func endpoint(for service: String) throws -> String {
        try awsEndpoint()
    }
}
