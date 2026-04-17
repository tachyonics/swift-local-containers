import ContainerTestSupport
import Foundation
import LocalContainers
import Testing

@testable import ContainerizationRuntime

import Containerization

private let containerizationAvailable: Bool = {
    // Check 1: a Linux kernel must be installed.
    let kernelsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent("com.apple.container/kernels")
    guard
        let contents = try? FileManager.default.contentsOfDirectory(
            at: kernelsDir,
            includingPropertiesForKeys: nil
        ),
        contents.contains(where: { $0.lastPathComponent.hasPrefix("vmlinux-") })
    else { return false }

    // Check 2: the process must hold the com.apple.vm.networking
    // entitlement (or equivalent) for vmnet to succeed. swift test
    // binaries aren't signed with this entitlement, so VmnetNetwork()
    // fails with status 1002. Try it once here and gate the tests on
    // the result so they skip gracefully rather than failing.
    if #available(macOS 26.0, *) {
        guard (try? VmnetNetwork()) != nil else {
            return false
        }
    }

    return true
}()

@Suite(
    .tags(.integration),
    .serialized,
    .enabled(
        if: containerizationAvailable,
        "Apple Containerization framework with a Linux kernel is required"
    )
)
struct ContainerizationRuntimeIntegrationTests {
    @Test("Pull, start, inspect, exec, logs, stop, and remove a container")
    func fullLifecycle() async throws {
        let runtime = ContainerizationContainerRuntime()
        let config = ContainerConfiguration(
            image: "alpine:latest",
            command: ["sleep", "30"],
            waitStrategy: .fixedDelay(.milliseconds(500)),
            waitTimeout: .seconds(15)
        )

        try await runtime.pullImage(config.image)
        let container = try await runtime.startContainer(from: config)

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        // Inspect: container should be running
        let inspection = try await runtime.inspect(container: container)
        #expect(inspection.isRunning == true)

        // Exec: run a command inside the container
        let exitCode = try await runtime.exec(
            command: ["echo", "hello from exec"],
            in: container
        )
        #expect(exitCode == 0)

        // Logs: should contain output from the exec
        let logs = try await runtime.logs(for: container)
        #expect(!logs.isEmpty)

        // Stop
        try await runtime.stopContainer(container)

        // Inspect after stop: should no longer be running
        let afterStop = try await runtime.inspect(container: container)
        #expect(afterStop.isRunning == false)

        // Remove
        try await runtime.removeContainer(container)
    }

    @Test("stopContainer throws containerNotFound for unknown ID")
    func stopUnknownContainer() async {
        let runtime = ContainerizationContainerRuntime()
        let fakeContainer = RunningContainer(
            id: "nonexistent-\(UUID().uuidString)",
            name: "fake",
            image: "alpine:latest",
            ports: []
        )

        await #expect(throws: ContainerError.self) {
            try await runtime.stopContainer(fakeContainer)
        }
    }

    @Test("Container with port mapping exposes the expected port")
    func portMapping() async throws {
        let runtime = ContainerizationContainerRuntime()
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

        try await WaitStrategyExecutor.waitUntilReady(
            container: container,
            configuration: config,
            runtime: runtime
        )

        let hostPort = try container.mappedPort(80)
        #expect(hostPort > 0)
    }
}
