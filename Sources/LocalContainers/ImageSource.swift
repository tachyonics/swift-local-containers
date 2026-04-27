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

    /// Build a `BuildSpec` whose `contextPath` is resolved relative to the
    /// nearest enclosing `Package.swift` walking upward from `callSiteFile`.
    ///
    /// Used by the `@DockerfileContainer` macro: callers pass `from: #filePath`
    /// at the call site so the resolved path is anchored at the user's package
    /// root, regardless of where the test target's source directory lives.
    /// Falls back to the literal `contextPath` if no `Package.swift` is found.
    public static func resolvedAgainstPackage(
        contextPath: String,
        from callSiteFile: String,
        dockerfile: String = "Dockerfile",
        tag: String
    ) -> BuildSpec {
        let resolved = resolvePackageRelative(path: contextPath, fromFile: callSiteFile)
        return BuildSpec(contextPath: resolved, dockerfile: dockerfile, tag: tag)
    }

}

private func resolvePackageRelative(path: String, fromFile: String) -> String {
    var dir = URL(fileURLWithPath: fromFile).deletingLastPathComponent()
    while dir.pathComponents.count > 1 {
        let pkg = dir.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: pkg.path) {
            return URL(fileURLWithPath: path, relativeTo: dir).standardized.path
        }
        dir = dir.deletingLastPathComponent()
    }
    return path
}
