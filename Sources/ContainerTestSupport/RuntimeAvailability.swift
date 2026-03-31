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
    let kernelsDir = homeDir
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent("com.apple.container/kernels")
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: kernelsDir, includingPropertiesForKeys: nil
    ) else { return false }
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
