import Containerization
import Foundation
import Synchronization

/// A ``Writer`` that accumulates all output into a thread-safe buffer.
///
/// Used to capture stdout/stderr from container processes so that logs
/// can be retrieved later via ``contents()``.
final class LogAccumulatingWriter: Writer, @unchecked Sendable {
    private let buffer = Mutex(Data())

    func write(_ data: Data) throws {
        buffer.withLock { $0.append(data) }
    }

    func close() throws {
        // Nothing to close — the buffer remains readable.
    }

    /// Returns the accumulated output as a UTF-8 string.
    func contents() -> String {
        let data = buffer.withLock { $0 }
        return String(decoding: data, as: UTF8.self)
    }
}
