import Logging
import Testing

@testable import LocalContainers

@Suite("LocalContainersLogging - parse")
struct LocalContainersLoggingParseTests {
    @Test(
        "Parses each spelled-out level (case-insensitive)",
        arguments: [
            ("trace", Logger.Level.trace),
            ("DEBUG", .debug),
            ("Info", .info),
            ("notice", .notice),
            ("warning", .warning),
            ("ERROR", .error),
            ("critical", .critical),
        ]
    )
    func recognizedLevels(raw: String, expected: Logger.Level) {
        #expect(LocalContainersLogging.parse(raw) == expected)
    }

    @Test("Returns nil for unrecognized strings")
    func unrecognized() {
        #expect(LocalContainersLogging.parse("verbose") == nil)
        #expect(LocalContainersLogging.parse("") == nil)
    }
}

@Suite("LocalContainersLogging - resolve")
struct LocalContainersLoggingResolveTests {
    @Test("nil raw value falls back to .info")
    func nilFallsBack() {
        #expect(LocalContainersLogging.resolve(raw: nil) == .info)
    }

    @Test("Recognized raw value resolves to that level")
    func recognized() {
        #expect(LocalContainersLogging.resolve(raw: "debug") == .debug)
        #expect(LocalContainersLogging.resolve(raw: "WARNING") == .warning)
    }

    @Test("Unrecognized raw value falls back to .info")
    func unrecognizedFallsBack() {
        #expect(LocalContainersLogging.resolve(raw: "verbose") == .info)
        #expect(LocalContainersLogging.resolve(raw: "") == .info)
    }
}
