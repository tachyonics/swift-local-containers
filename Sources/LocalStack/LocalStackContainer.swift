import Foundation
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
    ///
    /// The returned configuration uses exactly the ``environment`` passed
    /// to the initializer, with `SERVICES` derived from ``services`` and
    /// `DEBUG=1` added when no `LOCALSTACK_AUTH_TOKEN` is present. No
    /// values are read from the process environment; use
    /// ``environmentForwarding(_:merging:)`` to opt in to that.
    public func configuration() -> ContainerConfiguration {
        var env = environment
        if !services.isEmpty {
            env["SERVICES"] = services.joined(separator: ",")
        }
        // Enable debug logging when no auth token is provided. LocalStack
        // requires a token for all usage; DEBUG=1 surfaces the resulting
        // startup failure clearly in the logs.
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

    /// Builds an environment dictionary by forwarding selected keys from
    /// the current process environment, layered on top of an optional
    /// baseline. Forwarded shell values win over baseline values.
    ///
    /// Intended to be passed to ``init(image:services:environment:gatewayPort:)``
    /// when you want to opt in to shell environment forwarding:
    ///
    /// ```swift
    /// LocalStackContainer(
    ///     environment: LocalStackContainer.environmentForwarding(
    ///         overriding: LocalContainersConfig.values
    ///     )
    /// )
    /// ```
    public static func environmentForwarding(
        _ keys: [String] = ["LOCALSTACK_AUTH_TOKEN"],
        overriding baseline: [String: String] = [:]
    ) -> [String: String] {
        let processEnv = ProcessInfo.processInfo.environment
        var forwarded: [String: String] = [:]
        for key in keys {
            if let value = processEnv[key], !value.isEmpty {
                forwarded[key] = value
            }
        }
        return baseline.merging(forwarded) { _, shell in shell }
    }
}
