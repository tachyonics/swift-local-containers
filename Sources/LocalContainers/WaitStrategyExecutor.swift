import Logging

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Executes a ``WaitStrategy`` against a running container, blocking until
/// the container is ready or the timeout expires.
package enum WaitStrategyExecutor {
    /// Wait for the container to become ready according to its configured wait strategy.
    package static func waitUntilReady(
        container: RunningContainer,
        configuration: ContainerConfiguration,
        runtime: any ContainerRuntime,
        logger: Logger = Logger(label: "WaitStrategyExecutor")
    ) async throws {
        switch configuration.waitStrategy {
        case .port:
            try await waitForPort(
                container: container,
                timeout: configuration.waitTimeout,
                runtime: runtime,
                logger: logger
            )
        case .healthCheck:
            guard let healthCheck = configuration.healthCheck else {
                throw ContainerError.healthCheckFailed(
                    reason: "Health check wait strategy requires a healthCheck configuration"
                )
            }
            try await waitForHealthCheck(
                container: container,
                healthCheck: healthCheck,
                timeout: configuration.waitTimeout,
                runtime: runtime,
                logger: logger
            )
        case .log(let message):
            try await waitForLog(
                container: container,
                message: message,
                timeout: configuration.waitTimeout,
                runtime: runtime,
                logger: logger
            )
        case .fixedDelay(let duration):
            try await Task.sleep(for: duration)
        case .custom(let closure):
            try await closure(container)
        }
    }

    // MARK: - Port Strategy

    private static func waitForPort(
        container: RunningContainer,
        timeout: Duration,
        runtime: any ContainerRuntime,
        logger: Logger
    ) async throws {
        guard let firstPort = container.ports.first else {
            throw ContainerError.portNotFound(containerPort: 0)
        }

        try await pollWithTimeout(
            strategy: "port",
            timeout: timeout,
            pollInterval: .milliseconds(500),
            container: container,
            runtime: runtime,
            logger: logger
        ) {
            checkTCPPort(host: container.host, port: firstPort.hostPort)
        }
    }

    // MARK: - Health Check Strategy

    private static func waitForHealthCheck(
        container: RunningContainer,
        healthCheck: HealthCheckConfig,
        timeout: Duration,
        runtime: any ContainerRuntime,
        logger: Logger
    ) async throws {
        if healthCheck.startPeriod > .zero {
            try await Task.sleep(for: healthCheck.startPeriod)
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: timeout)
                await emitLogTail(
                    preamble: "Wait strategy 'healthCheck' timed out",
                    container: container,
                    runtime: runtime,
                    logger: logger
                )
                throw ContainerError.waitStrategyTimedOut(
                    strategy: "healthCheck",
                    timeout: timeout
                )
            }

            group.addTask {
                var failureCount = 0
                while !Task.isCancelled {
                    let inspection = try await runtime.inspect(container: container)
                    if !inspection.isRunning {
                        await emitLogTail(
                            preamble: "Container exited during wait",
                            container: container,
                            runtime: runtime,
                            logger: logger
                        )
                        throw ContainerError.containerExitedDuringWait(
                            exitCode: inspection.exitCode
                        )
                    }

                    let exitCode = try await runtime.exec(
                        command: healthCheck.test,
                        in: container
                    )
                    if exitCode == 0 {
                        return
                    }
                    failureCount += 1
                    if failureCount >= healthCheck.retries {
                        throw ContainerError.healthCheckFailed(
                            reason: "Health check failed after \(failureCount) consecutive attempts"
                        )
                    }
                    try await Task.sleep(for: healthCheck.interval)
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Log Strategy

    private static func waitForLog(
        container: RunningContainer,
        message: String,
        timeout: Duration,
        runtime: any ContainerRuntime,
        logger: Logger
    ) async throws {
        try await pollWithTimeout(
            strategy: "log",
            timeout: timeout,
            pollInterval: .seconds(1),
            container: container,
            runtime: runtime,
            logger: logger
        ) {
            let logs = try await runtime.logs(for: container)
            return logs.contains(message)
        }
    }

    // MARK: - Polling

    private static func pollWithTimeout(
        strategy: String,
        timeout: Duration,
        pollInterval: Duration,
        container: RunningContainer,
        runtime: any ContainerRuntime,
        logger: Logger,
        condition: @escaping @Sendable () async throws -> Bool
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: timeout)
                await emitLogTail(
                    preamble: "Wait strategy '\(strategy)' timed out",
                    container: container,
                    runtime: runtime,
                    logger: logger
                )
                throw ContainerError.waitStrategyTimedOut(
                    strategy: strategy,
                    timeout: timeout
                )
            }

            group.addTask {
                while !Task.isCancelled {
                    if try await condition() {
                        return
                    }

                    let inspection = try await runtime.inspect(container: container)
                    if !inspection.isRunning {
                        await emitLogTail(
                            preamble: "Container exited during wait",
                            container: container,
                            runtime: runtime,
                            logger: logger
                        )
                        throw ContainerError.containerExitedDuringWait(
                            exitCode: inspection.exitCode
                        )
                    }

                    try await Task.sleep(for: pollInterval)
                }
            }

            // First task to complete wins
            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Log Tail

    private static let maxLogTailLines = 20

    private static func emitLogTail(
        preamble: String,
        container: RunningContainer,
        runtime: any ContainerRuntime,
        logger: Logger
    ) async {
        guard let logs = try? await runtime.logs(for: container) else {
            return
        }
        let tail = tailLines(logs, count: maxLogTailLines)
        guard !tail.isEmpty else { return }

        let lineCount = tail.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        logger.error(
            "\(preamble). Last \(lineCount) log lines:",
            metadata: ["container": "\(container.id)"]
        )
        for line in tail.split(separator: "\n", omittingEmptySubsequences: false) {
            logger.error("\(line)", metadata: ["container": "\(container.id)"])
        }
    }

    static func tailLines(_ string: String, count: Int) -> String {
        let allLines = string.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        // Drop a single trailing empty element from a trailing newline
        let lines =
            allLines.last?.isEmpty == true
            ? allLines.dropLast()
            : allLines[...]
        let tail = lines.suffix(count)
        return tail.joined(separator: "\n")
    }

    // MARK: - TCP Port Check

    #if canImport(Glibc) || canImport(Musl)
    private static let sockStream = Int32(SOCK_STREAM.rawValue)
    #else
    private static let sockStream = SOCK_STREAM
    #endif

    static func checkTCPPort(host: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, sockStream, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // Set non-blocking so connect() returns immediately
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return false }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian

        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            return false
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }

        // EINPROGRESS means the connection is in progress — poll for completion
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        // Wait up to 500ms for the connection to complete
        let pollResult = poll(&pfd, 1, 500)
        guard pollResult > 0 else { return false }

        // Check if the connection actually succeeded via SO_ERROR
        var socketError: Int32 = 0
        var errorLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLen)

        return socketError == 0
    }
}
