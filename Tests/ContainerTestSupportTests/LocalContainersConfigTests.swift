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
