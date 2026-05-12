import AsyncHTTPClient
import Foundation
import Logging
import NIOCore

/// Streams a container's stdout+stderr from Docker's `/logs?follow=1` endpoint
/// and forwards each complete line to `logger` at `level`, tagged with
/// `container=<name>` metadata.
///
/// Returns when the stream closes (typically because the container has exited
/// and Docker hangs up the connection) or when the surrounding `Task` is
/// cancelled. Errors are swallowed and logged at debug level — streaming is
/// best-effort observability, never load-bearing for the test outcome.
///
/// Docker's non-TTY log frames are 8-byte prefixed
/// (`[stream_type(1), pad(3), size_be32]`), and the executor delivers them
/// in chunks of arbitrary boundary, so this implementation demuxes
/// incrementally across chunks rather than assuming whole frames per read.
package func streamContainerLogs(
    id: String,
    containerName: String,
    level: Logger.Level,
    socketPath: String,
    logger: Logger
) async {
    await streamContainerLogs(
        id: id,
        containerName: containerName,
        level: level,
        socketPath: socketPath,
        executor: HTTPClient.shared,
        logger: logger
    )
}

/// Generic-over-executor variant for testing. The package surface exposes
/// only the `HTTPClient.shared` overload above; tests inject a mock executor
/// to exercise the error paths (HTTP execute throws, non-2xx response,
/// trailing-line flush) without standing up a real Docker daemon.
package func streamContainerLogs<E: HTTPExecutor>(
    id: String,
    containerName: String,
    level: Logger.Level,
    socketPath: String,
    executor: E,
    logger: Logger
) async {
    let uri = "/v1.47/containers/\(id)/logs?follow=1&stdout=1&stderr=1"
    guard let url = URL(httpURLWithSocketPath: socketPath, uri: uri)?.absoluteString
    else {
        logger.debug(
            "Failed to build streaming log URL",
            metadata: ["container": "\(containerName)"]
        )
        return
    }
    var request = HTTPClientRequest(url: url)
    request.method = .GET
    request.headers.add(name: "Host", value: "localhost")

    do {
        let response = try await executor.execute(
            request,
            timeout: .hours(24),
            logger: nil
        )
        guard (200..<300).contains(Int(response.status.code)) else {
            logger.debug(
                "Log stream returned non-2xx",
                metadata: [
                    "container": "\(containerName)",
                    "status": "\(response.status.code)",
                ]
            )
            return
        }

        var demuxer = StreamingLogDemuxer()
        for try await chunk in response.body {
            demuxer.consume(chunk)
            for line in demuxer.takeLines() {
                logger.log(
                    level: level,
                    "\(line)",
                    metadata: ["container": "\(containerName)"]
                )
            }
            if Task.isCancelled { break }
        }
        if let trailing = demuxer.finish() {
            logger.log(
                level: level,
                "\(trailing)",
                metadata: ["container": "\(containerName)"]
            )
        }
    } catch is CancellationError {
        // Expected on container teardown.
    } catch {
        logger.debug(
            "Log stream ended with error",
            metadata: [
                "container": "\(containerName)",
                "error": "\(error)",
            ]
        )
    }
}

/// Incremental demuxer for Docker's multiplexed log frames.
///
/// Each frame: `[stream_type(1), pad(3), size_be32][payload size bytes]`.
/// `stream_type` is 0/1/2 (stdin/stdout/stderr). We don't currently
/// distinguish streams in the logger output, but the parsing has to consume
/// the header bytes anyway. Lines are split on `\n`; partial trailing lines
/// remain in the buffer for the next `consume`, and `finish()` flushes any
/// remainder.
struct StreamingLogDemuxer {
    private var pending = ByteBuffer()
    private var currentLine = ""
    private var state: State = .header

    private enum State {
        case header
        case payload(remaining: Int)
    }

    mutating func consume(_ chunk: ByteBuffer) {
        var chunk = chunk
        pending.writeBuffer(&chunk)
        drain()
    }

    mutating func takeLines() -> [String] {
        let lines = bufferedLines
        bufferedLines.removeAll(keepingCapacity: true)
        return lines
    }

    /// Returns any partial line still buffered at end-of-stream.
    mutating func finish() -> String? {
        currentLine.isEmpty ? nil : currentLine
    }

    private var bufferedLines: [String] = []

    private mutating func drain() {
        while true {
            switch state {
            case .header:
                guard pending.readableBytes >= 8 else { return }
                // First byte should be 0/1/2; if not, treat as plain text (TTY mode).
                let firstByte = pending.getInteger(at: pending.readerIndex, as: UInt8.self) ?? 0
                if firstByte > 2 {
                    if let text = pending.readString(length: pending.readableBytes) {
                        append(text)
                    }
                    return
                }
                _ = pending.readInteger(as: UInt32.self)  // stream type + padding
                guard let size = pending.readInteger(as: UInt32.self) else { return }
                state = .payload(remaining: Int(size))

            case .payload(let remaining):
                guard remaining > 0 else {
                    state = .header
                    continue
                }
                let toRead = min(remaining, pending.readableBytes)
                guard toRead > 0 else { return }
                if let text = pending.readString(length: toRead) {
                    append(text)
                }
                let left = remaining - toRead
                state = left == 0 ? .header : .payload(remaining: left)
            }
        }
    }

    private mutating func append(_ text: String) {
        var remaining = text[...]
        while let nl = remaining.firstIndex(of: "\n") {
            currentLine.append(contentsOf: remaining[..<nl])
            bufferedLines.append(currentLine)
            currentLine.removeAll(keepingCapacity: true)
            remaining = remaining[remaining.index(after: nl)...]
        }
        currentLine.append(contentsOf: remaining)
    }
}
