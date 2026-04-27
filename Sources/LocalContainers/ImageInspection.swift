/// A snapshot of an OCI image's metadata as reported by the runtime.
package struct ImageInspection: Sendable {
    /// Image identifier (e.g. `sha256:...`).
    package let id: String

    /// Ports declared as exposed in the image (from `EXPOSE` directives in the Dockerfile).
    package let exposedPorts: [ExposedPort]

    package init(id: String, exposedPorts: [ExposedPort]) {
        self.id = id
        self.exposedPorts = exposedPorts
    }
}

/// A port declared as exposed in an OCI image's metadata.
package struct ExposedPort: Sendable, Hashable {
    package let port: UInt16
    package let `protocol`: TransportProtocol

    package init(port: UInt16, protocol: TransportProtocol = .tcp) {
        self.port = port
        self.protocol = `protocol`
    }
}
