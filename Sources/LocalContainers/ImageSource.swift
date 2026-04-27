import Foundation

/// Where a container's image comes from.
///
/// `.reference` points at an image that the runtime should pull (or that
/// already exists in the local image store). `.build` points at a Dockerfile
/// and build context that should be built into a tagged local image before
/// the container is started.
public enum ImageSource: Sendable {
    /// An OCI image reference (e.g. `"localstack/localstack:latest"`).
    case reference(String)

    /// A Dockerfile-based image to be built locally before the container starts.
    case build(BuildSpec)

    /// The image tag to pass to `startContainer`. For `.reference`, the literal
    /// reference; for `.build`, the tag the build will assign to the resulting image.
    public var imageReference: String {
        switch self {
        case .reference(let ref):
            return ref
        case .build(let spec):
            return spec.tag
        }
    }
}

extension ImageSource: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .reference(value)
    }
}

/// Describes a Dockerfile-based image build.
///
/// The build context is a directory on the local filesystem; the Dockerfile
/// path is relative to that directory. The `tag` becomes the local image tag
/// that the container is started from.
public struct BuildSpec: Sendable {
    /// Filesystem path to the build context root (the directory that gets tarred and sent to the daemon).
    public let contextPath: String

    /// Path to the Dockerfile within the context.
    public let dockerfile: String

    /// Tag to assign to the built image (e.g. `"task-cluster:test"`).
    public let tag: String

    public init(contextPath: String, dockerfile: String = "Dockerfile", tag: String) {
        self.contextPath = contextPath
        self.dockerfile = dockerfile
        self.tag = tag
    }

    /// Package the build context directory as an uncompressed tar archive,
    /// suitable as the body of Docker's `POST /build` endpoint.
    ///
    /// Shells out to `tar` (resolved via `/usr/bin/env`) — assumes a POSIX-ish
    /// environment with `tar` on `PATH`. Honoring `.dockerignore` is not yet
    /// implemented; the entire context directory is included.
    public func tarContext() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tar", "-cf", "-", "-C", contextPath, "."]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw ContainerError.runtimeError(
                "Failed to launch tar for build context \(contextPath): \(error)"
            )
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ContainerError.runtimeError(
                "tar exited with status \(process.terminationStatus) for context \(contextPath): \(stderr)"
            )
        }
        return data
    }
}
