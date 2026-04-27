import LocalContainers
import Logging

/// Ensures an image is available locally — either by pulling or by building from a Dockerfile —
/// and returns the configuration to start the container with.
///
/// For `.build` sources, additionally inspects the resulting image and (if the
/// caller did not supply explicit ports) auto-derives port mappings from the
/// image's `EXPOSE` directives. Each declared port is mapped to a dynamic host port.
///
/// `runtime` is downcast to ``ImageBuildingRuntime`` for the build path; this
/// succeeds for the bundled runtimes (Docker, Containerization, PlatformRuntime)
/// and fails with `imageBuildNotSupported` for any user-supplied custom runtime
/// that doesn't conform.
package func prepareImage<R: ContainerRuntime>(
    for configuration: ContainerConfiguration,
    using runtime: R,
    logger: Logger
) async throws -> ContainerConfiguration {
    switch configuration.image {
    case .reference(let ref):
        try await runtime.pullImage(ref)
        return configuration

    case .build(let spec):
        guard let buildable = runtime as? ImageBuildingRuntime else {
            throw ContainerError.imageBuildNotSupported(
                reason:
                    "Runtime \(R.self) does not support building images. "
                    + "Use DockerContainerRuntime or PlatformRuntime."
            )
        }

        try await buildable.buildImage(spec: spec)

        let inspection = try await buildable.inspectImage(reference: spec.tag)
        guard configuration.ports.isEmpty, !inspection.exposedPorts.isEmpty else {
            return configuration
        }
        let derivedPorts = inspection.exposedPorts.map {
            PortMapping(containerPort: $0.port, hostPort: nil, protocol: $0.protocol)
        }
        return configuration.with(ports: derivedPorts)
    }
}
