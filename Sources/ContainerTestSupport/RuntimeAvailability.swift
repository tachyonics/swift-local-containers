import Foundation

public let dockerAvailable: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "docker info"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
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
