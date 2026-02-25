import Smockable
import Testing

@testable import LocalContainers

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// MARK: - Mock Runtime

@Smock(additionalEquatableTypes: [RunningContainer.self])
protocol TestContainerRuntime: ContainerRuntime {
    func pullImage(_ reference: String) async throws
    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer
    func stopContainer(_ container: RunningContainer) async throws
    func removeContainer(_ container: RunningContainer) async throws
    func inspect(container: RunningContainer) async throws -> ContainerInspection
    func logs(for container: RunningContainer) async throws -> String
}

private func makeNoOpMock() -> MockTestContainerRuntime {
    var expectations = MockTestContainerRuntime.Expectations()
    when(expectations.pullImage(.any), complete: .withSuccess)
    when(
        expectations.startContainer(from: .any),
        return: RunningContainer(id: "mock-1", name: "mock", image: "mock:latest")
    )
    when(expectations.stopContainer(.any), complete: .withSuccess)
    when(expectations.removeContainer(.any), complete: .withSuccess)
    when(
        expectations.inspect(container: .any),
        return: ContainerInspection(isRunning: true, healthStatus: .healthy)
    )
    when(expectations.logs(for: .any), return: "")
    return MockTestContainerRuntime(expectations: expectations)
}

// MARK: - TCP Helper

#if canImport(Glibc) || canImport(Musl)
private let sockStream = Int32(SOCK_STREAM.rawValue)
#else
private let sockStream = SOCK_STREAM
#endif

/// Creates a TCP listener on an OS-assigned port and returns (file descriptor, port).
private func createTCPListener() throws -> (fd: Int32, port: UInt16) {
    let fd = socket(AF_INET, sockStream, 0)
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

// MARK: - checkTCPPort Tests

@Suite("WaitStrategyExecutor - checkTCPPort")
struct CheckTCPPortTests {
    @Test("Returns false for invalid host address")
    func invalidHost() {
        let result = WaitStrategyExecutor.checkTCPPort(host: "not-an-ip", port: 80)
        #expect(result == false)
    }

    @Test("Returns true when listener is available on loopback")
    func immediateSuccess() throws {
        let (listenerFD, port) = try createTCPListener()
        defer { close(listenerFD) }

        let result = WaitStrategyExecutor.checkTCPPort(host: "127.0.0.1", port: port)
        #expect(result == true)
    }
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
        let runtime = makeNoOpMock()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
    }

    @Test("Port throws portNotFound when container has no ports")
    func portNoPorts() async {
        let container = RunningContainer(
            id: "test-noport",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: []
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .port,
            waitTimeout: .seconds(1)
        )
        let runtime = makeNoOpMock()

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .portNotFound(let port) = containerError
            else {
                return false
            }
            return port == 0
        }
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
        let runtime = makeNoOpMock()

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
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any), times: 1,
            return: ContainerInspection(isRunning: true, healthStatus: .starting)
        )
        when(
            expectations.inspect(container: .any),
            return: ContainerInspection(isRunning: true, healthStatus: .healthy)
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

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
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true, healthStatus: .starting)
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

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
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            return: ContainerInspection(isRunning: true, healthStatus: .unhealthy)
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

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
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.logs(for: .any),
            return: "Starting up...\nReady to accept connections\n"
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

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
        var expectations = MockTestContainerRuntime.Expectations()
        when(expectations.logs(for: .any), times: .unbounded, return: "Starting up...\n")
        let runtime = MockTestContainerRuntime(expectations: expectations)

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
        let runtime = makeNoOpMock()

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
        let runtime = makeNoOpMock()

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
