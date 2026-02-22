import Testing

@testable import LocalContainers

@Suite("HealthCheckConfig")
struct HealthCheckTests {
    @Test("Default intervals and retries")
    func defaults() {
        let hc = HealthCheckConfig(test: ["CMD", "curl", "-f", "http://localhost/"])

        #expect(hc.test == ["CMD", "curl", "-f", "http://localhost/"])
        #expect(hc.interval == .seconds(10))
        #expect(hc.timeout == .seconds(5))
        #expect(hc.retries == 3)
        #expect(hc.startPeriod == .seconds(0))
    }

    @Test("Custom values are preserved")
    func customValues() {
        let hc = HealthCheckConfig(
            test: ["CMD-SHELL", "pg_isready"],
            interval: .seconds(30),
            timeout: .seconds(10),
            retries: 5,
            startPeriod: .seconds(15)
        )

        #expect(hc.test == ["CMD-SHELL", "pg_isready"])
        #expect(hc.interval == .seconds(30))
        #expect(hc.timeout == .seconds(10))
        #expect(hc.retries == 5)
        #expect(hc.startPeriod == .seconds(15))
    }
}
