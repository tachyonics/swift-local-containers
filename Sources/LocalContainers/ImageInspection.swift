/// A snapshot of an OCI image's metadata as reported by the runtime.
public struct ImageInspection: Sendable {
    /// Image identifier (e.g. `sha256:...`).
    public let id: String

    /// Ports declared as exposed in the image (from `EXPOSE` directives in the Dockerfile).
    public let exposedPorts: [ExposedPort]

    public init(id: String, exposedPorts: [ExposedPort]) {
        self.id = id
        self.exposedPorts = exposedPorts
    }
}

/// A port declared as exposed in an OCI image's metadata.
public struct ExposedPort: Sendable, Hashable {
    public let port: UInt16
    public let `protocol`: TransportProtocol

    public init(port: UInt16, protocol: TransportProtocol = .tcp) {
        self.port = port
        self.protocol = `protocol`
    }
}
