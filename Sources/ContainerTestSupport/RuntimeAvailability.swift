import Foundation

public let dockerAvailable: Bool = {
    // Standard Linux daemon socket (also what CI jobs typically mount
    // from the host).
    if FileManager.default.fileExists(atPath: "/var/run/docker.sock") {
        return true
    }
    // Docker Desktop on macOS.
    let desktopSocket = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".docker/run/docker.sock").path
    if FileManager.default.fileExists(atPath: desktopSocket) {
        return true
    }
    // Explicitly configured daemon (remote host, colima, rootless).
    if let dockerHost = ProcessInfo.processInfo.environment["DOCKER_HOST"],
        !dockerHost.isEmpty
    {
        return true
    }
    return false
}()

#if canImport(ContainerizationRuntime)
public let containerizationAvailable: Bool = {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let kernelsDir =
        homeDir
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent("com.apple.container/kernels")
    guard
        let contents = try? FileManager.default.contentsOfDirectory(
            at: kernelsDir,
            includingPropertiesForKeys: nil
        )
    else { return false }
    return contents.contains { $0.lastPathComponent.hasPrefix("vmlinux-") }
}()
#endif

public let containerRuntimeAvailable: Bool = {
    #if canImport(ContainerizationRuntime)
    return containerizationAvailable
    #else
    return dockerAvailable
    #endif
}()

/// Whether a LocalStack auth token is available, either from the
/// environment or from `.local-containers/env`. LocalStack requires an
/// auth token to start.
public let localStackAuthTokenAvailable: Bool = {
    isAuthTokenAvailable(
        fromEnvironment: ProcessInfo.processInfo.environment["LOCALSTACK_AUTH_TOKEN"],
        fromConfig: LocalContainersConfig.value(for: "LOCALSTACK_AUTH_TOKEN")
    )
}()

/// Pure predicate used by ``localStackAuthTokenAvailable``. Exposed for testing.
func isAuthTokenAvailable(
    fromEnvironment envValue: String?,
    fromConfig configValue: String?
)
    -> Bool
{
    if let envValue, !envValue.isEmpty { return true }
    return configValue?.isEmpty == false
}
