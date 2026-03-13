import Foundation

let dockerAvailable: Bool = shellCommandSucceeds("docker info")
let npmAvailable: Bool = shellCommandSucceeds("which npm")

func shellCommandSucceeds(_ command: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}
