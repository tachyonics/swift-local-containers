import Testing

/// A minimal `TestScoping` trait to reproduce the `_recursivelyApplyTraits`
/// crash on Linux CI. If this crashes, it's a Swift Testing bug — not our code.
private struct MinimalTrait: SuiteTrait, TestScoping {
    let isRecursive = true

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing execute: @Sendable () async throws -> Void
    ) async throws {
        try await execute()
    }
}

@Suite("MinimalTrait reproducer", MinimalTrait())
struct MinimalTraitTests {
    @Test("placeholder test to exercise TestScoping")
    func placeholder() {
        #expect(true)
    }
}
