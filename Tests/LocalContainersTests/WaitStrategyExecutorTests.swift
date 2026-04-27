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
    func exec(command: [String], in container: RunningContainer) async throws -> Int32
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
        times: .unbounded,
        return: ContainerInspection(isRunning: true)
    )
    when(expectations.exec(command: .any, in: .any), return: Int32(0))
    when(expectations.logs(for: .any), times: .unbounded, return: "")
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

/// Accepts a single connection on the listener, reads the request, writes
/// a hardcoded HTTP/1.1 response, and closes. Returns when the connection completes.
private func runOneShotHTTPResponder(
    listenerFD: Int32,
    status: Int = 200,
    body: String = "ok"
) {
    var clientAddr = sockaddr_in()
    var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            accept(listenerFD, sockaddrPtr, &clientLen)
        }
    }
    guard clientFD >= 0 else { return }
    defer { close(clientFD) }

    var buf = [UInt8](repeating: 0, count: 1024)
    _ = buf.withUnsafeMutableBufferPointer { read(clientFD, $0.baseAddress, $0.count) }

    let response =
        "HTTP/1.1 \(status) X\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    let bytes = Array(response.utf8)
    _ = bytes.withUnsafeBufferPointer { write(clientFD, $0.baseAddress, $0.count) }
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

    @Test("Returns false when nothing is listening on port")
    func noListener() throws {
        // Bind and immediately close to obtain a port that is very likely unused.
        let (listenerFD, port) = try createTCPListener()
        close(listenerFD)

        let result = WaitStrategyExecutor.checkTCPPort(host: "127.0.0.1", port: port)
        #expect(result == false)
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

    @Test("Port throws containerExitedDuringWait when container exits mid-wait")
    func portContainerExits() async {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: false, status: "exited", exitCode: 42)
        )
        when(
            expectations.logs(for: .any),
            times: .unbounded,
            return: "boom1\nboom2\n"
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let container = RunningContainer(
            id: "test-port-exit",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: 1)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .port,
            waitTimeout: .seconds(5)
        )

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .containerExitedDuringWait(let exitCode) = containerError
            else {
                return false
            }
            return exitCode == 42
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
    private static let healthCheck = HealthCheckConfig(
        test: ["CMD", "curl", "-f", "http://localhost/"],
        interval: .milliseconds(100),
        timeout: .seconds(5),
        retries: 3,
        startPeriod: .zero
    )

    @Test("Health check throws when healthCheck config is nil")
    func healthCheckMissingConfig() async {
        let runtime = makeNoOpMock()

        let container = RunningContainer(id: "test-hc-nil", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            waitTimeout: .seconds(5)
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

    @Test("Health check succeeds after non-zero then zero exit code")
    func healthCheckSucceeds() async throws {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
        when(expectations.exec(command: .any, in: .any), times: 1, return: Int32(1))
        when(expectations.exec(command: .any, in: .any), return: Int32(0))
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let container = RunningContainer(id: "test-3", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: Self.healthCheck,
            waitTimeout: .seconds(10)
        )

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
    }

    @Test("Health check times out when exec always returns non-zero")
    func healthCheckTimesOut() async {
        var expectations = MockTestContainerRuntime.Expectations()
        // Return non-zero but fewer times than retries threshold so it doesn't
        // throw healthCheckFailed before the timeout fires
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
        when(expectations.exec(command: .any, in: .any), times: .unbounded, return: Int32(1))
        when(expectations.logs(for: .any), return: "")
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let highRetriesHealthCheck = HealthCheckConfig(
            test: ["CMD", "curl", "-f", "http://localhost/"],
            interval: .milliseconds(100),
            timeout: .seconds(5),
            retries: 1000,
            startPeriod: .zero
        )

        let container = RunningContainer(id: "test-4", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: highRetriesHealthCheck,
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

    @Test("Health check throws containerExitedDuringWait when container exits mid-wait")
    func healthCheckContainerExits() async {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: false, status: "exited", exitCode: 7)
        )
        when(expectations.logs(for: .any), times: .unbounded, return: "crash\n")
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let container = RunningContainer(id: "test-hc-exit", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: Self.healthCheck,
            waitTimeout: .seconds(5)
        )

        await #expect {
            try await WaitStrategyExecutor.waitUntilReady(
                container: container,
                configuration: config,
                runtime: runtime
            )
        } throws: { error in
            guard let containerError = error as? ContainerError,
                case .containerExitedDuringWait(let exitCode) = containerError
            else {
                return false
            }
            return exitCode == 7
        }
    }

    @Test("Health check honours startPeriod before polling")
    func healthCheckStartPeriod() async throws {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
        when(expectations.exec(command: .any, in: .any), times: .unbounded, return: Int32(0))
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let startPeriod: Duration = .milliseconds(150)
        let hc = HealthCheckConfig(
            test: ["CMD", "true"],
            interval: .milliseconds(100),
            timeout: .seconds(5),
            retries: 3,
            startPeriod: startPeriod
        )

        let container = RunningContainer(id: "test-hc-sp", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: hc,
            waitTimeout: .seconds(10)
        )

        let start = ContinuousClock.now
        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
        let elapsed = ContinuousClock.now - start

        #expect(elapsed >= startPeriod)
    }

    @Test("Health check timeout emits log tail when logs are non-empty")
    func healthCheckTimeoutEmitsLogTail() async {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
        when(expectations.exec(command: .any, in: .any), times: .unbounded, return: Int32(1))
        when(
            expectations.logs(for: .any),
            times: .unbounded,
            return: "log-a\nlog-b\nlog-c\n"
        )
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let highRetriesHealthCheck = HealthCheckConfig(
            test: ["CMD", "false"],
            interval: .milliseconds(100),
            timeout: .seconds(5),
            retries: 1000,
            startPeriod: .zero
        )

        let container = RunningContainer(id: "test-hc-tail", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: highRetriesHealthCheck,
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

    @Test("Health check fails after reaching retries threshold")
    func healthCheckFailsOnRetries() async {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
        when(expectations.exec(command: .any, in: .any), times: .unbounded, return: Int32(1))
        let runtime = MockTestContainerRuntime(expectations: expectations)

        let container = RunningContainer(id: "test-5", name: "test", image: "test:latest")
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .healthCheck,
            healthCheck: Self.healthCheck,
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
        when(
            expectations.inspect(container: .any),
            times: .unbounded,
            return: ContainerInspection(isRunning: true)
        )
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

// MARK: - tailLines Tests

@Suite("WaitStrategyExecutor - tailLines")
struct TailLinesTests {
    @Test("Returns last N lines from multi-line string")
    func lastNLines() {
        let logs = "line1\nline2\nline3\nline4\nline5"
        let result = WaitStrategyExecutor.tailLines(logs, count: 3)
        #expect(result == "line3\nline4\nline5")
    }

    @Test("Returns full string when fewer lines than count")
    func fewerLinesThanCount() {
        let logs = "line1\nline2"
        let result = WaitStrategyExecutor.tailLines(logs, count: 5)
        #expect(result == "line1\nline2")
    }

    @Test("Handles trailing newline without extra empty line")
    func trailingNewline() {
        let logs = "line1\nline2\nline3\n"
        let result = WaitStrategyExecutor.tailLines(logs, count: 2)
        #expect(result == "line2\nline3")
    }

    @Test("Returns empty string for empty input")
    func emptyInput() {
        let result = WaitStrategyExecutor.tailLines("", count: 5)
        #expect(result == "")
    }

    @Test("Single line with no newline")
    func singleLine() {
        let result = WaitStrategyExecutor.tailLines("only line", count: 3)
        #expect(result == "only line")
    }
}

/// Thread-safe mutable flag for testing.
private actor Flag {
    var value = false
    func set() { value = true }
}

// MARK: - HTTP GET Strategy Tests

@Suite("WaitStrategyExecutor - HTTPGet")
struct HTTPGetStrategyTests {
    @Test("HTTP GET succeeds when responder returns expected status")
    func httpGetSucceeds() async throws {
        let (listenerFD, port) = try createTCPListener()
        defer { close(listenerFD) }

        let responder = Task.detached {
            runOneShotHTTPResponder(listenerFD: listenerFD, status: 200)
        }

        let container = RunningContainer(
            id: "test-http-1",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: port)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .httpGet(path: "/health"),
            waitTimeout: .seconds(5)
        )
        let runtime = makeNoOpMock()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
        await responder.value
    }

    @Test("HTTP GET succeeds with custom expected status")
    func httpGetCustomStatus() async throws {
        let (listenerFD, port) = try createTCPListener()
        defer { close(listenerFD) }

        let responder = Task.detached {
            runOneShotHTTPResponder(listenerFD: listenerFD, status: 204)
        }

        let container = RunningContainer(
            id: "test-http-2",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: port)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .httpGet(path: "/health", expectedStatus: 204),
            waitTimeout: .seconds(5)
        )
        let runtime = makeNoOpMock()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
        await responder.value
    }

    @Test("HTTP GET times out when nothing is listening")
    func httpGetTimesOut() async throws {
        // Bind and immediately close to obtain a port that is very likely unused.
        let (listenerFD, port) = try createTCPListener()
        close(listenerFD)

        let container = RunningContainer(
            id: "test-http-3",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: port)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .httpGet(path: "/health"),
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
            return strategy == "httpGet"
        }
    }

    @Test("HTTP GET throws portNotFound when container has no ports")
    func httpGetNoPorts() async {
        let container = RunningContainer(
            id: "test-http-noport",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: []
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .httpGet(path: "/health"),
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
                case .portNotFound = containerError
            else {
                return false
            }
            return true
        }
    }

    @Test("HTTP GET normalizes path without leading slash")
    func httpGetPathNormalization() async throws {
        let (listenerFD, port) = try createTCPListener()
        defer { close(listenerFD) }

        let responder = Task.detached {
            runOneShotHTTPResponder(listenerFD: listenerFD, status: 200)
        }

        let container = RunningContainer(
            id: "test-http-4",
            name: "test",
            image: "test:latest",
            host: "127.0.0.1",
            ports: [ResolvedPortMapping(containerPort: 8080, hostPort: port)]
        )
        let config = ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .httpGet(path: "health"),  // no leading slash
            waitTimeout: .seconds(5)
        )
        let runtime = makeNoOpMock()

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )
        await responder.value
    }
}
