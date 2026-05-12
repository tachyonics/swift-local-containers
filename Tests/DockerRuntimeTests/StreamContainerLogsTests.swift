import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import NIOHTTP1
import Smockable
import Testing

@testable import DockerRuntime

/// Custom logger handler that captures log records into an array so the
/// streaming tests can assert what was emitted (level + message + metadata)
/// without spinning up a real Docker daemon.
final class CapturingLogHandler: LogHandler, @unchecked Sendable {
    struct Record: Equatable {
        let level: Logger.Level
        let message: String
        let metadata: [String: String]
    }

    private let lock = NSLock()
    private var _records: [Record] = []
    var records: [Record] {
        lock.withLock { _records }
    }

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.MetadataValue? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source _: String,
        file _: String,
        function _: String,
        line _: UInt
    ) {
        let merged = metadata ?? [:]
        let stringified = merged.reduce(into: [String: String]()) { acc, kv in
            acc[kv.key] = "\(kv.value)"
        }
        lock.withLock {
            _records.append(
                Record(
                    level: level,
                    message: "\(message)",
                    metadata: stringified
                )
            )
        }
    }
}

private func makeCapturingLogger() -> (Logger, CapturingLogHandler) {
    let handler = CapturingLogHandler()
    let logger = Logger(label: "test-streaming") { _ in handler }
    return (logger, handler)
}

private func mockExecutor(
    behavior: (inout MockTestHTTPExecutor.Expectations) -> Void
) -> MockTestHTTPExecutor {
    var expectations = MockTestHTTPExecutor.Expectations()
    behavior(&expectations)
    return MockTestHTTPExecutor(expectations: expectations)
}

@Suite("streamContainerLogs - error paths")
struct StreamContainerLogsErrorPathTests {
    @Test("Executor throwing on execute is caught and logged at debug")
    func executorThrows() async {
        let (logger, capture) = makeCapturingLogger()
        struct BoomError: Error {}
        let executor = mockExecutor { expectations in
            when(
                expectations.execute(.any, timeout: .any, logger: .any),
                throw: BoomError()
            )
        }

        await streamContainerLogs(
            id: "abc",
            containerName: "svc",
            level: .info,
            socketPath: "/var/run/docker.sock",
            executor: executor,
            logger: logger
        )

        let matching = capture.records.filter { record in
            record.level == .debug
                && record.message.contains("Log stream ended with error")
                && record.metadata["container"] == "svc"
        }
        #expect(!matching.isEmpty)
    }

    @Test("Non-2xx response logs at debug and returns silently")
    func non2xxResponse() async {
        let (logger, capture) = makeCapturingLogger()
        let executor = mockExecutor { expectations in
            when(
                expectations.execute(.any, timeout: .any, logger: .any),
                return: HTTPClientResponse(
                    status: .notFound,
                    body: .bytes(ByteBuffer(string: ""))
                )
            )
        }

        await streamContainerLogs(
            id: "abc",
            containerName: "svc",
            level: .info,
            socketPath: "/var/run/docker.sock",
            executor: executor,
            logger: logger
        )

        let matching = capture.records.filter { record in
            record.level == .debug
                && record.message.contains("Log stream returned non-2xx")
                && record.metadata["status"] == "404"
        }
        #expect(!matching.isEmpty)
    }
}

@Suite("streamContainerLogs - success path")
struct StreamContainerLogsSuccessTests {
    /// Build one Docker stdout frame: `[1,0,0,0,size_be32]` + payload bytes.
    private func frame(_ payload: String) -> ByteBuffer {
        var buf = ByteBuffer()
        buf.writeInteger(UInt8(1))  // stdout
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt32(payload.utf8.count))
        buf.writeString(payload)
        return buf
    }

    @Test("Emits each demuxed line via logger at the configured level")
    func successfulStream() async {
        let (logger, capture) = makeCapturingLogger()
        var body = ByteBuffer()
        var oneFrame = frame("alpha\nbeta\n")
        body.writeBuffer(&oneFrame)
        let executor = mockExecutor { expectations in
            when(
                expectations.execute(.any, timeout: .any, logger: .any),
                return: HTTPClientResponse(
                    status: .ok,
                    body: .bytes(body)
                )
            )
        }

        await streamContainerLogs(
            id: "abc",
            containerName: "svc",
            level: .info,
            socketPath: "/var/run/docker.sock",
            executor: executor,
            logger: logger
        )

        let lines = capture.records.filter { $0.level == .info }
            .map(\.message)
        #expect(lines == ["alpha", "beta"])
    }

    @Test("Trailing partial line is flushed by finish() at end of stream")
    func trailingPartialFlushed() async {
        let (logger, capture) = makeCapturingLogger()
        // No trailing newline — exercises the `if let trailing = demuxer.finish()` path.
        var body = ByteBuffer()
        var oneFrame = frame("only-line-no-newline")
        body.writeBuffer(&oneFrame)
        let executor = mockExecutor { expectations in
            when(
                expectations.execute(.any, timeout: .any, logger: .any),
                return: HTTPClientResponse(
                    status: .ok,
                    body: .bytes(body)
                )
            )
        }

        await streamContainerLogs(
            id: "abc",
            containerName: "svc",
            level: .info,
            socketPath: "/var/run/docker.sock",
            executor: executor,
            logger: logger
        )

        let lines = capture.records.filter { $0.level == .info }
            .map(\.message)
        #expect(lines == ["only-line-no-newline"])
    }
}
