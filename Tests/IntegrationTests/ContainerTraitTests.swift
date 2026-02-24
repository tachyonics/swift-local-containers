import ContainerTestSupport
import DockerRuntime
import LocalContainers
import Testing

/// Integration test that exercises the full container lifecycle including
/// wait strategy execution, mirroring the code path in `ContainerTrait.provideScope`.
@Suite(.tags(.integration, .docker))
struct ContainerTraitTests {
    @Test("Port wait strategy succeeds with nginx container")
    func portWaitStrategy() async throws {
        let runtime = DockerContainerRuntime()
        let config = ContainerConfiguration(
            image: "nginx:alpine",
            ports: [PortMapping(containerPort: 80)],
            waitStrategy: .port,
            waitTimeout: .seconds(30)
        )

        try await runtime.pullImage(config.image)
        let container = try await runtime.startContainer(from: config)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        // This is the code path exercised by ContainerTrait.provideScope
        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        #expect(!container.id.isEmpty)
        #expect(container.image == "nginx:alpine")

        let hostPort = try container.mappedPort(80)
        #expect(hostPort > 0)
    }

    @Test("Log wait strategy succeeds with nginx container")
    func logWaitStrategy() async throws {
        let runtime = DockerContainerRuntime()
        let config = ContainerConfiguration(
            image: "nginx:alpine",
            ports: [PortMapping(containerPort: 80)],
            waitStrategy: .log("start worker process"),
            waitTimeout: .seconds(30)
        )

        try await runtime.pullImage(config.image)
        let container = try await runtime.startContainer(from: config)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        let logs = try await runtime.logs(for: container)
        #expect(logs.contains("start worker process"))
    }

    @Test("inspect returns running state for active container")
    func inspectRunningContainer() async throws {
        let runtime = DockerContainerRuntime()
        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sleep", "30"],
            waitStrategy: .fixedDelay(.milliseconds(500))
        )

        try await runtime.pullImage(config.image)
        let container = try await runtime.startContainer(from: config)

        defer {
            Task {
                try? await runtime.stopContainer(container)
                try? await runtime.removeContainer(container)
            }
        }

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        let inspection = try await runtime.inspect(container: container)
        #expect(inspection.isRunning == true)
        #expect(inspection.healthStatus == .notConfigured)
    }
}
