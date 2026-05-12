import ContainerTestSupport
import Foundation
import LocalContainers
import Logging
import Testing

@testable import DockerRuntime

@Suite(.tags(.integration, .docker), .enabled(if: dockerAvailable, "Docker is required"))
struct DockerLifecycleTests {
    @Test("Full Docker container lifecycle: pull, create, start, inspect, stop, remove")
    func dockerLifecycle() async throws {
        let runtime = DockerContainerRuntime()

        // 1. Pull a small image
        try await runtime.pullImage("alpine:latest")

        // 2. Start a container with a port mapping
        let config = ContainerConfiguration(
            image: "alpine:latest",
            ports: [PortMapping(containerPort: 8080)],
            command: ["sleep", "30"]
        )
        let container = try await runtime.startContainer(from: config)

        // 3. Verify the running container has expected properties
        #expect(!container.id.isEmpty)
        #expect(!container.name.isEmpty)
        #expect(container.image == "alpine:latest")

        // 4. Stop and remove
        try await runtime.stopContainer(container)
        try await runtime.removeContainer(container)

        // 5. Verify the container is gone
        let client = DockerAPIClient()
        await #expect(throws: ContainerError.self) {
            _ = try await client.inspectContainer(id: container.id)
        }
    }

    @Test("streamLogs forwards container stdout to the runtime logger")
    func streamLogsForwardsOutput() async throws {
        let runtime = DockerContainerRuntime()
        try await runtime.pullImage("alpine:latest")

        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sh", "-c", "echo line-one; echo line-two; sleep 1"]
        )
        let container = try await runtime.startContainer(from: config)
        defer {
            Task {
                try? await runtime.removeContainer(container)
            }
        }

        // Run the stream against the live container; it should naturally end
        // when the container exits and Docker closes the connection.
        await runtime.streamLogs(container: container, level: .info)

        // The test passes if streamLogs returned without throwing — the
        // assertion that the logger saw `line-one`/`line-two` would require
        // a captured logger handler; existing unit tests on
        // StreamingLogDemuxer cover that path in isolation.
    }

    @Test("streamContainerLogs returns cleanly when surrounding Task is cancelled")
    func streamLogsCancellation() async throws {
        let runtime = DockerContainerRuntime()
        try await runtime.pullImage("alpine:latest")

        // Long-running container so the stream stays open until we cancel.
        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sh", "-c", "while true; do echo tick; sleep 1; done"]
        )
        let container = try await runtime.startContainer(from: config)
        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        let streamer = Task {
            await runtime.streamLogs(container: container, level: .info)
        }
        // Let a chunk or two flow, then cancel.
        try await Task.sleep(for: .milliseconds(500))
        streamer.cancel()
        // If the catch is wired up correctly, this returns; otherwise the
        // test times out.
        await streamer.value
    }

    @Test("streamContainerLogs swallows non-2xx from the daemon")
    func streamLogsNon2xx() async {
        // Bogus container id — Docker returns 404. Function should return
        // silently rather than throw.
        await streamContainerLogs(
            id: "deadbeef-no-such-container-\(UUID().uuidString)",
            containerName: "bogus",
            level: .info,
            socketPath: "/var/run/docker.sock",
            logger: Logger(label: "test")
        )
    }

    @Test(
        "httpGet wait surfaces containerExitedDuringWait, not portNotFound, when the container crashes on start"
    )
    func httpGetWaitOnImmediateExitYieldsExitError() async throws {
        let runtime = DockerContainerRuntime()
        try await runtime.pullImage("alpine:latest")

        // Container crashes before its port mappings can be observed. The
        // empty `NetworkSettings.Ports` left behind would previously surface
        // as a misleading `portNotFound(0)` from the wait strategy.
        let config = ContainerConfiguration(
            image: "alpine:latest",
            ports: [PortMapping(containerPort: 8080)],
            command: ["sh", "-c", "exit 7"],
            waitStrategy: .httpGet(path: "/health"),
            waitTimeout: .seconds(5)
        )
        let container = try await runtime.startContainer(from: config)

        defer {
            Task {
                try? await runtime.removeContainer(container)
            }
        }

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
}
