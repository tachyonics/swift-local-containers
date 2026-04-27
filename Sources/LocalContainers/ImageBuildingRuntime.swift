import Foundation

/// A ``ContainerRuntime`` that can additionally build images from a Dockerfile
/// and inspect image metadata.
///
/// This is an internal extension point used by the trait/macro machinery for
/// Dockerfile-based service containers. It is intentionally `package`-scoped:
/// end-users compose with the public ``ContainerRuntime`` protocol; the
/// build/inspect surface is an implementation detail of swift-local-containers.
package protocol ImageBuildingRuntime: ContainerRuntime {
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
}
