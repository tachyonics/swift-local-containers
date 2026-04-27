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
/// Streams stdout to `logger.debug` and collects stderr for error reporting.
/// On non-zero exit, throws ``ContainerError/imageBuildFailed(tag:reason:)``
/// with the trimmed tail of stderr.
func runDockerBuild(spec: BuildSpec, logger: Logger) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "docker", "build",
        "--tag", spec.tag,
        "--file", "\(spec.contextPath)/\(spec.dockerfile)",
        spec.contextPath
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
            "dockerfile": "\(spec.dockerfile)"
        ]
    )

    let stdoutTask = Task {
        await streamPipe(
            stdoutPipe.fileHandleForReading,
            label: "docker build stdout",
            logger: logger,
            collectTail: false
        )
    }
    let stderrTask = Task {
        await streamPipe(
            stderrPipe.fileHandleForReading,
            label: "docker build stderr",
            logger: logger,
            collectTail: true
        )
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

private func streamPipe(
    _ handle: FileHandle,
    label: String,
    logger: Logger,
    collectTail: Bool
) async -> String {
    var tail = ""
    let maxTail = 8 * 1024
    do {
        for try await line in handle.bytes.lines {
            logger.debug("\(label)", metadata: ["line": "\(line)"])
            if collectTail {
                tail += line + "\n"
                if tail.count > maxTail {
                    tail = String(tail.suffix(maxTail))
                }
            }
        }
    } catch {
        logger.debug("\(label) read failed", metadata: ["error": "\(error)"])
    }
    return tail
}
