import ContainerTestSupport
import Foundation
import Testing

@testable import LocalContainers
@testable import PlatformRuntime

// API tests only run on platforms where PlatformRuntime delegates to Docker,
// since ContainerizationContainerRuntime is not yet fully implemented.
#if !canImport(ContainerizationRuntime)
@Suite(
    "PlatformRuntime API",
    .tags(.integration, .docker),
    .enabled(if: dockerAvailable, "Docker is required")
)
struct PlatformRuntimeAPITests {
    let runtime = PlatformRuntime()

    @Test("pullImage pulls without error")
    func pullImage() async throws {
        try await runtime.pullImage("alpine:latest")
    }

    @Test("startContainer and stopContainer manage lifecycle")
    func startAndStop() async throws {
        try await runtime.pullImage("alpine:latest")

        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sleep", "30"]
        )
        let container = try await runtime.startContainer(from: config)
        #expect(!container.id.isEmpty)
        #expect(container.image == "alpine:latest")

        try await runtime.stopContainer(container)
        try await runtime.removeContainer(container)
    }

    @Test("inspect returns running state")
    func inspect() async throws {
        try await runtime.pullImage("alpine:latest")

        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sleep", "30"],
            waitStrategy: .fixedDelay(.milliseconds(500))
        )
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
        #expect(inspection.isRunning)
    }

    @Test("logs returns container output")
    func logs() async throws {
        try await runtime.pullImage("alpine:latest")

        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["echo", "hello from PlatformRuntime"],
            waitStrategy: .fixedDelay(.milliseconds(500))
        )
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

        let output = try await runtime.logs(for: container)
        #expect(output.contains("hello from PlatformRuntime"))
    }
}
#endif
