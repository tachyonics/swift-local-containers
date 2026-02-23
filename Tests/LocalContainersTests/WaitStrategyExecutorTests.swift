#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import Testing

@testable import LocalContainers

// MARK: - Mock Runtime

private final class MockContainerRuntime: ContainerRuntime, @unchecked Sendable {
    var inspectionResults: [ContainerInspection] = []
    var logResults: [String] = []
    private var inspectCallCount = 0
    private var logsCallCount = 0

    func pullImage(_ reference: String) async throws {}

    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer {
        RunningContainer(id: "mock-1", name: "mock", image: "mock:latest")
    }

    func stopContainer(_ container: RunningContainer) async throws {}
    func removeContainer(_ container: RunningContainer) async throws {}

    func inspectContainer(_ container: RunningContainer) async throws -> ContainerInspection {
        let index = min(inspectCallCount, inspectionResults.count - 1)
        inspectCallCount += 1
        return inspectionResults[index]
    }

    func containerLogs(_ container: RunningContainer) async throws -> String {
        let index = min(logsCallCount, logResults.count - 1)
        logsCallCount += 1
        return logResults[index]
    }
}

// MARK: - TCP Helper

/// Creates a TCP listener on an OS-assigned port and returns (file descriptor, port).
private func createTCPListener() throws -> (fd: Int32, port: UInt16) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw ContainerError.runtimeError("Failed to create socket")
    }

    var opt: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0  // OS-assigned
    addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else {
        close(fd)
        throw ContainerError.runtimeError("Failed to bind socket")
    }

    guard listen(fd, 1) == 0 else {
        close(fd)
        throw ContainerError.runtimeError("Failed to listen on socket")
    }

    // Get the assigned port
    var boundAddr = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            getsockname(fd, sockaddrPtr, &len)
        }
    }

    return (fd, UInt16(bigEndian: boundAddr.sin_port))
}

// MARK: - Port Strategy Tests

@Suite("WaitStrategyExecutor - Port")
struct PortStrategyTests {
    @Test("Port succeeds when listener is available")
    func portSucceeds() async throws {
        let (listenerFD, port) = try createTCPListener()
        defer { close(listenerFD) }

        let container = RunningContainer(
            id: "test-1",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: port)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .port,
            waitTimeout: .seconds(5)
        )
        let runtime = MockContainerRuntime()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
    }

    @Test("Port times out when no listener")
    func portTimesOut() async {
        let container = RunningContainer(
            id: "test-2",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: 1)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .port,
            waitTimeout: .seconds(1)
        )
        let runtime = MockContainerRuntime()

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .waitStrategyTimedOut(let strategy, _) = containerError
            else {
                return false
            }
            return strategy == "port"
        }
    }
}

// MARK: - Health Check Strategy Tests

@Suite("WaitStrategyExecutor - HealthCheck")
struct HealthCheckStrategyTests {
    @Test("Health check succeeds after starting then healthy")
    func healthCheckSucceeds() async throws {
        let runtime = MockContainerRuntime()
        runtime.inspectionResults = [
            ContainerInspection(isRunning: true, healthStatus: .starting),
            ContainerInspection(isRunning: true, healthStatus: .healthy),
        ]

        let container = RunningContainer(id: "test-3", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            waitTimeout: .seconds(10)
        )

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
    }

    @Test("Health check times out when always starting")
    func healthCheckTimesOut() async {
        let runtime = MockContainerRuntime()
        runtime.inspectionResults = [
            ContainerInspection(isRunning: true, healthStatus: .starting)
        ]

        let container = RunningContainer(id: "test-4", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            waitTimeout: .seconds(1)
        )

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .waitStrategyTimedOut(let strategy, _) = containerError
            else {
                return false
            }
            return strategy == "healthCheck"
        }
    }

    @Test("Health check fails on unhealthy")
    func healthCheckFailsOnUnhealthy() async {
        let runtime = MockContainerRuntime()
        runtime.inspectionResults = [
            ContainerInspection(isRunning: true, healthStatus: .unhealthy)
        ]

        let container = RunningContainer(id: "test-5", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            waitTimeout: .seconds(10)
        )

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .healthCheckFailed = containerError
            else {
                return false
            }
            return true
        }
    }
}

// MARK: - Log Strategy Tests

@Suite("WaitStrategyExecutor - Log")
struct LogStrategyTests {
    @Test("Log message found in output")
    func logMessageFound() async throws {
        let runtime = MockContainerRuntime()
        runtime.logResults = [
            "Starting up...\nReady to accept connections\n"
        ]

        let container = RunningContainer(id: "test-6", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .log("Ready to accept connections"),
            waitTimeout: .seconds(5)
        )

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
    }

    @Test("Log times out when message not present")
    func logTimesOut() async {
        let runtime = MockContainerRuntime()
        runtime.logResults = [
            "Starting up...\n"
        ]

        let container = RunningContainer(id: "test-7", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .log("Ready"),
            waitTimeout: .seconds(1)
        )

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .waitStrategyTimedOut(let strategy, _) = containerError
            else {
                return false
            }
            return strategy == "log"
        }
    }
}

// MARK: - Fixed Delay Strategy Tests

@Suite("WaitStrategyExecutor - FixedDelay")
struct FixedDelayStrategyTests {
    @Test("Fixed delay waits for the specified duration")
    func fixedDelayWaits() async throws {
        let container = RunningContainer(id: "test-8", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .fixedDelay(.milliseconds(100)),
            waitTimeout: .seconds(5)
        )
        let runtime = MockContainerRuntime()

        let start = ContinuousClock.now
        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
        let elapsed = ContinuousClock.now - start

        #expect(elapsed >= .milliseconds(80))
    }
}

// MARK: - Custom Strategy Tests

@Suite("WaitStrategyExecutor - Custom")
struct CustomStrategyTests {
    @Test("Custom closure is called with the container")
    func customClosureCalled() async throws {
        let flag = Flag()

        let container = RunningContainer(id: "test-9", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .custom { c in
                #expect(c.id == "test-9")
                await flag.set()
            },
            waitTimeout: .seconds(5)
        )
        let runtime = MockContainerRuntime()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        let value = await flag.value
        #expect(value == true)
    }
}

/// Thread-safe mutable flag for testing.
private actor Flag {
    var value = false
    func set() { value = true }
}
