import Foundation
import Testing

@testable import ContainerizationRuntime

@Suite("LogAccumulatingWriter")
struct LogAccumulatingWriterTests {
    @Test("Empty writer returns empty string")
    func emptyContents() {
        let writer = LogAccumulatingWriter()
        #expect(writer.contents().isEmpty)
    }

    @Test("Single write is readable via contents()")
    func singleWrite() throws {
        let writer = LogAccumulatingWriter()
        try writer.write(Data("hello".utf8))
        #expect(writer.contents() == "hello")
    }

    @Test("Multiple writes concatenate in order")
    func multipleWrites() throws {
        let writer = LogAccumulatingWriter()
        try writer.write(Data("hello ".utf8))
        try writer.write(Data("world".utf8))
        #expect(writer.contents() == "hello world")
    }

    @Test("close() does not clear the buffer")
    func closePreservesBuffer() throws {
        let writer = LogAccumulatingWriter()
        try writer.write(Data("before close".utf8))
        try writer.close()
        #expect(writer.contents() == "before close")
    }

    @Test("contents() is repeatable — reading does not drain the buffer")
    func contentsIsRepeatable() throws {
        let writer = LogAccumulatingWriter()
        try writer.write(Data("persistent".utf8))
        #expect(writer.contents() == "persistent")
        #expect(writer.contents() == "persistent")
    }

    @Test("Concurrent writes from multiple tasks produce all expected data")
    func concurrentWrites() async throws {
        let writer = LogAccumulatingWriter()
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    try? writer.write(Data("line\(i)\n".utf8))
                }
            }
        }

        let contents = writer.contents()
        let lines = contents.split(separator: "\n")
        #expect(lines.count == iterations)
    }
}
