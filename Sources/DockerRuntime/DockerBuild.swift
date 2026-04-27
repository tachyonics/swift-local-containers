import Foundation
import LocalContainers
import Logging

/// Build an OCI image by shelling out to the local `docker` CLI.
///
/// Why shell-out instead of Docker's REST `/build` endpoint: modern Dockerfiles
/// commonly use BuildKit features (`# syntax=docker/dockerfile:1`,
/// `RUN --mount=type=cache`, secrets, etc.) which the legacy Engine API
/// builder rejects, and BuildKit-over-REST requires a hijacked-HTTP gRPC
/// session protocol that's substantial to implement. The `docker` CLI handles
/// all of this transparently.
///
/// Streams stdout/stderr to `logger.debug` line-by-line as the build runs and
/// collects the stderr tail for error reporting. On non-zero exit, throws
/// ``ContainerError/imageBuildFailed(tag:reason:)`` with the trimmed tail of
/// stderr.
func runDockerBuild(spec: BuildSpec, logger: Logger) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "docker", "build",
        "--tag", spec.tag,
        "--file", "\(spec.contextPath)/\(spec.dockerfile)",
        spec.contextPath,
    ]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    logger.info(
        "Building image",
        metadata: [
            "tag": "\(spec.tag)",
            "context": "\(spec.contextPath)",
            "dockerfile": "\(spec.dockerfile)",
        ]
    )

    // Drain pipes on detached threads so a build with > 64KB of output
    // doesn't deadlock waiting for the kernel pipe buffer to drain.
    let stdoutHandle = stdoutPipe.fileHandleForReading
    let stderrHandle = stderrPipe.fileHandleForReading

    let stdoutTask = Task.detached(priority: .background) {
        drainPipeSync(stdoutHandle, label: "docker build", logger: logger, collectTail: false)
    }
    let stderrTask = Task.detached(priority: .background) {
        drainPipeSync(stderrHandle, label: "docker build", logger: logger, collectTail: true)
    }

    let exitCode: Int32
    do {
        exitCode = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { proc in
                cont.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    } catch {
        throw ContainerError.imageBuildFailed(
            tag: spec.tag,
            reason: "Failed to launch docker: \(error). Is the docker CLI installed and on PATH?"
        )
    }

    _ = await stdoutTask.value
    let stderrTail = await stderrTask.value

    guard exitCode == 0 else {
        let trimmed = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ContainerError.imageBuildFailed(
            tag: spec.tag,
            reason: trimmed.isEmpty
                ? "docker build exited with status \(exitCode)"
                : trimmed
        )
    }
}

@Sendable
private func drainPipeSync(
    _ handle: FileHandle,
    label: String,
    logger: Logger,
    collectTail: Bool
) -> String {
    var tail = ""
    let maxTail = 8 * 1024
    while true {
        let data = handle.availableData
        if data.isEmpty { break }  // EOF — writer (the process) closed the pipe.
        let str = String(decoding: data, as: UTF8.self)
        for line in str.split(separator: "\n", omittingEmptySubsequences: true) {
            logger.debug("\(label)", metadata: ["line": "\(line)"])
        }
        if collectTail {
            tail += str
            if tail.count > maxTail {
                tail = String(tail.suffix(maxTail))
            }
        }
    }
    return tail
}
