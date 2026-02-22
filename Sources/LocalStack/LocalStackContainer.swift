import LocalContainers

/// Pre-configured ``ContainerConfiguration`` builder for LocalStack.
public struct LocalStackContainer: Sendable {
    /// The LocalStack image to use.
    public let image: String

    /// AWS services to activate in LocalStack.
    public let services: [String]

    /// Additional environment variables.
    public let environment: [String: String]

    /// The gateway port (default 4566).
    public let gatewayPort: UInt16

    public init(
        image: String = "localstack/localstack:latest",
        services: [String] = [],
        environment: [String: String] = [:],
        gatewayPort: UInt16 = 4566
    ) {
        self.image = image
        self.services = services
        self.environment = environment
        self.gatewayPort = gatewayPort
    }

    /// Build the ``ContainerConfiguration`` for this LocalStack instance.
    public func configuration() -> ContainerConfiguration {
        var env = environment
        if !services.isEmpty {
            env["SERVICES"] = services.joined(separator: ",")
        }
        // Activate pro features only if a key is provided
        if env["LOCALSTACK_AUTH_TOKEN"] == nil {
            env["DEBUG"] = env["DEBUG"] ?? "1"
        }

        return ContainerConfiguration(
            image: image,
            ports: [PortMapping(containerPort: gatewayPort)],
            environment: env,
            waitStrategy: .log("Ready.")
        )
    }
}
