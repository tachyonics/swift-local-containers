import Foundation
import Testing

@testable import ContainerTestSupport

@Suite("LocalContainersConfig - parse")
struct LocalContainersConfigParseTests {
    @Test("Parses simple KEY=VALUE lines")
    func simplePairs() {
        let result = LocalContainersConfig.parse("FOO=bar\nBAZ=qux")
        #expect(result.count == 2)
        #expect(result[0].key == "FOO")
        #expect(result[0].value == "bar")
        #expect(result[1].key == "BAZ")
        #expect(result[1].value == "qux")
    }

    @Test("Skips blank lines and comments")
    func blankAndComments() {
        let contents = """
            # a comment
            FOO=bar

              # indented comment
            BAZ=qux
            """
        let result = LocalContainersConfig.parse(contents)
        #expect(result.map(\.key) == ["FOO", "BAZ"])
    }

    @Test("Strips surrounding double and single quotes")
    func stripsQuotes() {
        let result = LocalContainersConfig.parse(#"A="hello"\#nB='world'\#nC=raw"#)
        #expect(result[0].value == "hello")
        #expect(result[1].value == "world")
        #expect(result[2].value == "raw")
    }

    @Test("Trims whitespace around key and value")
    func trimsWhitespace() {
        let result = LocalContainersConfig.parse("  FOO  =  bar  ")
        #expect(result.count == 1)
        #expect(result[0].key == "FOO")
        #expect(result[0].value == "bar")
    }

    @Test("Ignores lines without equals sign")
    func ignoresMalformed() {
        let result = LocalContainersConfig.parse("notAKeyValueLine\nFOO=bar")
        #expect(result.count == 1)
        #expect(result[0].key == "FOO")
    }

    @Test("Ignores lines with empty key")
    func ignoresEmptyKey() {
        let result = LocalContainersConfig.parse("=noKey\nFOO=bar")
        #expect(result.count == 1)
        #expect(result[0].key == "FOO")
    }

    @Test("Preserves equals signs inside values")
    func equalsInValue() {
        let result = LocalContainersConfig.parse("URL=https://example.com/?q=1&r=2")
        #expect(result.count == 1)
        #expect(result[0].value == "https://example.com/?q=1&r=2")
    }
}

@Suite("LocalContainersConfig - load")
struct LocalContainersConfigLoadTests {
    @Test("Returns empty dict when file does not exist")
    func missingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/env")
        let result = LocalContainersConfig.load(from: url)
        #expect(result.isEmpty)
    }

    @Test("Parses KEY=VALUE pairs from existing file")
    func existingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("env")
        try """
        # header comment
        FOO=bar
        TOKEN="secret"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let result = LocalContainersConfig.load(from: fileURL)
        #expect(result["FOO"] == "bar")
        #expect(result["TOKEN"] == "secret")
        #expect(result.count == 2)
    }
}

@Suite("LocalContainersConfig - public accessors")
struct LocalContainersConfigAccessorTests {
    @Test("values and value(for:) are consistent")
    func accessorsAgree() {
        let all = LocalContainersConfig.values
        // `values` reads from the project-local .local-containers/env at
        // CWD. We don't assert a specific key — just that the two public
        // accessors agree for every key present.
        for (key, expected) in all {
            #expect(LocalContainersConfig.value(for: key) == expected)
        }
    }

    @Test("value(for:) returns nil for missing keys")
    func missingKey() {
        let result = LocalContainersConfig.value(
            for: "DEFINITELY_NOT_A_REAL_KEY_\(UUID().uuidString)"
        )
        #expect(result == nil)
    }
}
