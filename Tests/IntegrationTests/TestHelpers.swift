import ContainerTestSupport
import Foundation

let npmAvailable: Bool = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "which npm"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}()

/// The Docker socket path on the host. LocalStack needs this mounted to
/// spawn sibling containers for Lambda execution.
let dockerSocketPath = "/var/run/docker.sock"

/// Whether the Docker socket is accessible at ``dockerSocketPath``. Used
/// to gate tests that require Docker-in-Docker (e.g. Lambda in LocalStack).
/// Returns false on rootless Docker setups, macOS Colima with non-default
/// socket paths, or any environment where the socket isn't at the standard
/// location.
let dockerSocketAvailable: Bool = {
    FileManager.default.fileExists(atPath: dockerSocketPath)
}()
