import Foundation
import NIOCore
import Testing

@testable import DockerRuntime

@Suite("StreamingLogDemuxer")
struct StreamingLogDemuxerTests {
    @Test("Single frame, single line")
    func singleFrameSingleLine() {
        var demuxer = StreamingLogDemuxer()
        demuxer.consume(frame(stream: 1, payload: "hello\n"))
        #expect(demuxer.takeLines() == ["hello"])
        #expect(demuxer.finish() == nil)
    }

    @Test("Single frame, multiple lines")
    func singleFrameMultipleLines() {
        var demuxer = StreamingLogDemuxer()
        demuxer.consume(frame(stream: 1, payload: "one\ntwo\nthree\n"))
        #expect(demuxer.takeLines() == ["one", "two", "three"])
    }

    @Test("Frame header split across chunks")
    func headerSplit() {
        var demuxer = StreamingLogDemuxer()
        let full = frame(stream: 1, payload: "hi\n")
        var first = ByteBuffer(bytes: full.getBytes(at: 0, length: 3) ?? [])
        var second = ByteBuffer(bytes: full.getBytes(at: 3, length: full.readableBytes - 3) ?? [])
        demuxer.consume(first)
        #expect(demuxer.takeLines() == [])
        demuxer.consume(second)
        #expect(demuxer.takeLines() == ["hi"])
        _ = first.readableBytes  // silence unused warnings
        _ = second.readableBytes
    }

    @Test("Payload split across chunks")
    func payloadSplit() {
        var demuxer = StreamingLogDemuxer()
        let full = frame(stream: 1, payload: "hello world\n")
        let cut = 8 + 5  // header + "hello"
        let first = ByteBuffer(bytes: full.getBytes(at: 0, length: cut) ?? [])
        let second = ByteBuffer(bytes: full.getBytes(at: cut, length: full.readableBytes - cut) ?? [])
        demuxer.consume(first)
        #expect(demuxer.takeLines() == [])
        demuxer.consume(second)
        #expect(demuxer.takeLines() == ["hello world"])
    }

    @Test("Line spanning two frames")
    func lineSpanningFrames() {
        var demuxer = StreamingLogDemuxer()
        demuxer.consume(frame(stream: 1, payload: "abc"))
        demuxer.consume(frame(stream: 2, payload: "def\n"))
        #expect(demuxer.takeLines() == ["abcdef"])
    }

    @Test("Partial trailing line flushed by finish()")
    func partialTrailingLine() {
        var demuxer = StreamingLogDemuxer()
        demuxer.consume(frame(stream: 1, payload: "no newline"))
        #expect(demuxer.takeLines() == [])
        #expect(demuxer.finish() == "no newline")
    }

    @Test("TTY-mode (no framing) plain text passes through")
    func ttyModePlainText() {
        var demuxer = StreamingLogDemuxer()
        // 8 bytes starting with a non-{0,1,2} byte signals TTY/plain.
        var buf = ByteBuffer()
        buf.writeString("Hello world!\nsecond line\n")
        demuxer.consume(buf)
        #expect(demuxer.takeLines() == ["Hello world!", "second line"])
    }

    private func frame(stream: UInt8, payload: String) -> ByteBuffer {
        var buf = ByteBuffer()
        buf.writeInteger(stream)
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt8(0))
        buf.writeInteger(UInt32(payload.utf8.count))
        buf.writeString(payload)
        return buf
    }
}
