import Foundation

/// A backend capable of pulling images and managing container lifecycles.
///
/// Implementations exist for Docker/Podman (via REST API) and Apple's
/// Containerization framework. User code should generally interact with
/// `PlatformRuntime` rather than a concrete backend directly.
public protocol ContainerRuntime: Sendable {
    /// Pull an OCI image so it is available locally.
    func pullImage(_ reference: String) async throws

    /// Build an OCI image from a tarred build context.
    ///
    /// Throws ``ContainerError/imageBuildNotSupported(reason:)`` on runtimes
    /// that have no programmatic build path (e.g. Apple Containerization).
    ///
    /// - Parameters:
    ///   - contextTar: Build context as an uncompressed tar archive.
    ///   - dockerfile: Path to the Dockerfile within the context (default `"Dockerfile"`).
    ///   - tag: Tag to assign to the built image.
    func buildImage(contextTar: Data, dockerfile: String, tag: String) async throws

    /// Inspect an OCI image by reference and return its metadata.
    ///
    /// Used to discover declared `EXPOSE` ports for service-container port auto-mapping.
    func inspectImage(reference: String) async throws -> ImageInspection

    /// Create and start a container from the given configuration.
    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer

    /// Stop a running container.
    func stopContainer(_ container: RunningContainer) async throws

    /// Remove a stopped container and its associated resources.
    func removeContainer(_ container: RunningContainer) async throws

    /// Inspect a running container and return its current state.
    func inspect(container: RunningContainer) async throws -> ContainerInspection

    /// Execute a command inside a running container and return the exit code.
    func exec(command: [String], in container: RunningContainer) async throws -> Int32

    /// Fetch the log output from a container.
    func logs(for container: RunningContainer) async throws -> String
}
