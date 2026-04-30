/// A resolved port mapping showing the actual host port assigned by the runtime.
public struct ResolvedPortMapping: Sendable, Hashable {
    /// The port inside the container.
    public let containerPort: UInt16

    /// The actual port on the host assigned by the runtime.
    public let hostPort: UInt16

    /// The protocol for this mapping.
    public let `protocol`: TransportProtocol

    public init(containerPort: UInt16, hostPort: UInt16, protocol: TransportProtocol = .tcp) {
        self.containerPort = containerPort
        self.hostPort = hostPort
        self.protocol = `protocol`
    }
}

/// A snapshot of a running container's state. Value type — the runtime owns the actual lifecycle.
public struct RunningContainer: Sendable, Equatable {
    /// Runtime-assigned container identifier.
    public let id: String

    /// The container name.
    public let name: String

    /// The image the container was started from.
    public let image: String

    /// The host address to connect to from the test runner (typically
    /// `"127.0.0.1"`, or the Docker bridge gateway when the test runner
    /// itself is inside a container).
    public let host: String

    /// The Docker bridge gateway IP for this container's network, when the
    /// runtime can determine one. Reachable from sibling containers on the
    /// same bridge — the right host to use in URLs that cross-container env
    /// injection plumbs into a sibling. `nil` when the runtime doesn't
    /// expose one (custom networks, non-Docker runtimes, etc.).
    public let bridgeGateway: String?

    /// Resolved port mappings with actual host ports.
    public let ports: [ResolvedPortMapping]

    public init(
        id: String,
        name: String,
        image: String,
        host: String = "127.0.0.1",
        bridgeGateway: String? = nil,
        ports: [ResolvedPortMapping] = []
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.host = host
        self.bridgeGateway = bridgeGateway
        self.ports = ports
    }

    /// Returns the host port mapped to the given container port.
    ///
    /// - Throws: ``ContainerError/portNotFound(containerPort:)`` if no mapping exists.
    public func mappedPort(_ containerPort: UInt16) throws -> UInt16 {
        guard let mapping = ports.first(where: { $0.containerPort == containerPort }) else {
            throw ContainerError.portNotFound(containerPort: containerPort)
        }
        return mapping.hostPort
    }
}
