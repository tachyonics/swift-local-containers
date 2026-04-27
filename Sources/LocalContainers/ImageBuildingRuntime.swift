/// A ``ContainerRuntime`` that can additionally build images from a Dockerfile
/// and inspect image metadata.
///
/// This is an internal extension point used by the trait/macro machinery for
/// Dockerfile-based service containers. It is intentionally `package`-scoped:
/// end-users compose with the public ``ContainerRuntime`` protocol; the
/// build/inspect surface is an implementation detail of swift-local-containers.
package protocol ImageBuildingRuntime: ContainerRuntime {
    /// Build an OCI image from a Dockerfile-based ``BuildSpec``.
    ///
    /// Implementations are expected to support BuildKit features that modern
    /// Dockerfiles depend on (`# syntax=docker/dockerfile:1`,
    /// `RUN --mount=type=cache`, etc.). The default `DockerContainerRuntime`
    /// implementation shells out to the local `docker` CLI for this reason.
    ///
    /// Throws ``ContainerError/imageBuildNotSupported(reason:)`` on runtimes
    /// that have no programmatic build path (e.g. Apple Containerization).
    func buildImage(spec: BuildSpec) async throws

    /// Inspect an OCI image by reference and return its metadata.
    ///
    /// Used to discover declared `EXPOSE` ports for service-container port auto-mapping.
    func inspectImage(reference: String) async throws -> ImageInspection
}
