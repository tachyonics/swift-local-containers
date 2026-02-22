import Synchronization
import Testing

@testable import LocalContainers

@Suite("WaitStrategy")
struct WaitStrategyTests {
    @Test("Log strategy stores the expected string")
    func logStrategy() {
        let strategy = WaitStrategy.log("Ready.")

        if case .log(let message) = strategy {
            #expect(message == "Ready.")
        } else {
            Issue.record("Expected .log strategy")
        }
    }

    @Test("Fixed delay strategy stores the duration")
    func fixedDelayStrategy() {
        let strategy = WaitStrategy.fixedDelay(.seconds(5))

        if case .fixedDelay(let duration) = strategy {
            #expect(duration == .seconds(5))
        } else {
            Issue.record("Expected .fixedDelay strategy")
        }
    }

    @Test("Port strategy is constructable")
    func portStrategy() {
        let strategy = WaitStrategy.port

        if case .port = strategy {
            // pass
        } else {
            Issue.record("Expected .port strategy")
        }
    }

    @Test("HealthCheck strategy is constructable")
    func healthCheckStrategy() {
        let strategy = WaitStrategy.healthCheck

        if case .healthCheck = strategy {
            // pass
        } else {
            Issue.record("Expected .healthCheck strategy")
        }
    }

    @Test("Custom strategy executes closure")
    func customStrategy() async throws {
        let called = Mutex(false)
        let strategy = WaitStrategy.custom { _ in
            called.withLock { $0 = true }
        }

        if case .custom(let closure) = strategy {
            let container = RunningContainer(id: "x", name: "x", image: "x")
            try await closure(container)
            #expect(called.withLock { $0 })
        } else {
            Issue.record("Expected .custom strategy")
        }
    }
}
