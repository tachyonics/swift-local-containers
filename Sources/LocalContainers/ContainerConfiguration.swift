/// A mapping between a container port and a host port.
public struct PortMapping: Sendable, Hashable {
    /// The port inside the container.
    public let containerPort: UInt16

    /// The port on the host. When `nil`, the runtime assigns a random available port.
    public let hostPort: UInt16?

    /// The protocol for this port mapping.
    public let `protocol`: TransportProtocol

    public init(
        containerPort: UInt16,
        hostPort: UInt16? = nil,
        protocol: TransportProtocol = .tcp
    ) {
        self.containerPort = containerPort
        self.hostPort = hostPort
        self.protocol = `protocol`
    }
}

/// Transport protocol for port mappings.
public enum TransportProtocol: String, Sendable, Hashable {
    case tcp
    case udp
}

/// A volume mount binding a host path to a container path.
public struct VolumeMount: Sendable, Hashable {
    /// Path on the host.
    public let hostPath: String

    /// Path inside the container.
    public let containerPath: String

    /// Whether the mount is read-only inside the container.
    public let readOnly: Bool

    public init(hostPath: String, containerPath: String, readOnly: Bool = false) {
        self.hostPath = hostPath
        self.containerPath = containerPath
        self.readOnly = readOnly
    }
}

/// Configuration describing the desired state of a container before it is started.
public struct ContainerConfiguration: Sendable {
    /// OCI image reference (e.g. `"localstack/localstack:latest"`).
    public let image: String

    /// Port mappings from container ports to host ports.
    public let ports: [PortMapping]

    /// Environment variables passed to the container.
    public let environment: [String: String]

    /// Volume mounts.
    public let volumes: [VolumeMount]

    /// Optional container name. When `nil`, the runtime generates a unique name.
    public let name: String?

    /// Command override. When `nil`, the image's default entrypoint/cmd is used.
    public let command: [String]?

    /// Strategy used to wait for the container to become ready.
    public let waitStrategy: WaitStrategy

    /// Health check configuration.
    public let healthCheck: HealthCheckConfig?

    /// Maximum time to wait for the container to become ready.
    public let waitTimeout: Duration

    public init(
        image: String,
        ports: [PortMapping] = [],
        environment: [String: String] = [:],
        volumes: [VolumeMount] = [],
        name: String? = nil,
        command: [String]? = nil,
        waitStrategy: WaitStrategy = .port,
        healthCheck: HealthCheckConfig? = nil,
        waitTimeout: Duration = .seconds(60)
    ) {
        self.image = image
        self.ports = ports
        self.environment = environment
        self.volumes = volumes
        self.name = name
        self.command = command
        self.waitStrategy = waitStrategy
        self.healthCheck = healthCheck
        self.waitTimeout = waitTimeout
    }
}
