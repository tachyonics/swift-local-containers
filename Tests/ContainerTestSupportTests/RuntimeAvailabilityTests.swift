import Testing

@testable import ContainerTestSupport

@Suite("isAuthTokenAvailable")
struct IsAuthTokenAvailableTests {
    @Test("Returns true when env value is non-empty")
    func envNonEmpty() {
        #expect(isAuthTokenAvailable(fromEnvironment: "ls-abc", fromConfig: nil))
    }

    @Test("Env wins over config when both present")
    func envPreferredOverConfig() {
        #expect(isAuthTokenAvailable(fromEnvironment: "ls-env", fromConfig: "ls-config"))
    }

    @Test("Falls back to config when env is nil")
    func falsEnvNil() {
        #expect(isAuthTokenAvailable(fromEnvironment: nil, fromConfig: "ls-config"))
    }

    @Test("Falls back to config when env is empty string")
    func envEmpty() {
        #expect(isAuthTokenAvailable(fromEnvironment: "", fromConfig: "ls-config"))
    }

    @Test("Returns false when both sources are absent")
    func bothMissing() {
        #expect(isAuthTokenAvailable(fromEnvironment: nil, fromConfig: nil) == false)
    }

    @Test("Returns false when both sources are empty")
    func bothEmpty() {
        #expect(isAuthTokenAvailable(fromEnvironment: "", fromConfig: "") == false)
    }
}
