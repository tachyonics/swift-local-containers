import Containerization
import Logging

/// Manages VM and image resources for the Containerization backend.
///
/// This is currently a stub. The full implementation will handle:
/// - OCI image storage and caching
/// - VM lifecycle management
/// - Network and port forwarding configuration
public actor ContainerizationManager {
    private let logger: Logger

    public init(logger: Logger = Logger(label: "ContainerizationManager")) {
        self.logger = logger
    }
}
