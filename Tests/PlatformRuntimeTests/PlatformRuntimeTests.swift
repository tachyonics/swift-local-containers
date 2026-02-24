import Testing

@testable import LocalContainers
@testable import PlatformRuntime

private actor StubContainerRuntime: ContainerRuntime {
    var pulledImages: [String] = []
    var startedConfigs: [ContainerConfiguration] = []
    var stoppedIDs: [String] = []
    var removedIDs: [String] = []
    var inspectedIDs: [String] = []
    var logRequestedIDs: [String] = []

    let stubbedContainer: RunningContainer

    init(
        stubbedContainer: RunningContainer = RunningContainer(
            id: "stub-1",
            name: "stub",
            image: "stub:latest",
            ports: [ResolvedPortMapping(containerPort: 80, hostPort: 32000)]
        )
    ) {
        self.stubbedContainer = stubbedContainer
    }

    func pullImage(_ reference: String) async throws {
        pulledImages.append(reference)
    }

    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer {
        startedConfigs.append(configuration)
        return stubbedContainer
    }

    func stopContainer(_ container: RunningContainer) async throws {
        stoppedIDs.append(container.id)
    }

    func removeContainer(_ container: RunningContainer) async throws {
        removedIDs.append(container.id)
    }

    func inspect(container: RunningContainer) async throws -> ContainerInspection {
        inspectedIDs.append(container.id)
        return ContainerInspection(isRunning: true, healthStatus: .healthy)
    }

    func logs(for container: RunningContainer) async throws -> String {
        logRequestedIDs.append(container.id)
        return ""
    }
}

@Suite("PlatformRuntime")
struct PlatformRuntimeTests {
    @Test("pullImage delegates to underlying runtime")
    func pullDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)

        try await runtime.pullImage("nginx:latest")

        #expect(await stub.pulledImages == ["nginx:latest"])
    }

    @Test("startContainer delegates and returns the result")
    func startDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)

        let config = ContainerConfiguration(image: "redis:7")
        let container = try await runtime.startContainer(from: config)

        let startedConfigs = await stub.startedConfigs
        #expect(startedConfigs.count == 1)
        #expect(startedConfigs[0].image == "redis:7")
        #expect(container.id == "stub-1")
    }

    @Test("stopContainer delegates to underlying runtime")
    func stopDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-1", name: "test", image: "test")

        try await runtime.stopContainer(container)

        #expect(await stub.stoppedIDs == ["c-1"])
    }

    @Test("removeContainer delegates to underlying runtime")
    func removeDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-2", name: "test", image: "test")

        try await runtime.removeContainer(container)

        #expect(await stub.removedIDs == ["c-2"])
    }

    @Test("inspectContainer delegates to underlying runtime")
    func inspectDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-3", name: "test", image: "test")

        let inspection = try await runtime.inspect(container: container)

        #expect(await stub.inspectedIDs == ["c-3"])
        #expect(inspection.isRunning == true)
        #expect(inspection.healthStatus == .healthy)
    }

    @Test("containerLogs delegates to underlying runtime")
    func logsDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-4", name: "test", image: "test")

        let logs = try await runtime.logs(for: container)

        #expect(await stub.logRequestedIDs == ["c-4"])
        #expect(logs == "")
    }

    @Test("Errors from underlying runtime propagate")
    func errorPropagation() async {
        let stub = StubContainerRuntime()
        // Override pull to throw
        let throwingRuntime = ThrowingRuntime()
        let runtime = PlatformRuntime(runtime: throwingRuntime)

        _ = stub  // suppress warning

        await #expect(throws: ContainerError.self) {
            try await runtime.pullImage("bad:image")
        }
    }
}

private struct ThrowingRuntime: ContainerRuntime {
    func pullImage(_ reference: String) async throws {
        throw ContainerError.imagePullFailed(image: reference, reason: "stubbed error")
    }

    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer {
        throw ContainerError.startFailed(reason: "stubbed error")
    }

    func stopContainer(_ container: RunningContainer) async throws {
        throw ContainerError.runtimeError("stubbed error")
    }

    func removeContainer(_ container: RunningContainer) async throws {
        throw ContainerError.runtimeError("stubbed error")
    }

    func inspect(container: RunningContainer) async throws -> ContainerInspection {
        throw ContainerError.runtimeError("stubbed error")
    }

    func logs(for container: RunningContainer) async throws -> String {
        throw ContainerError.runtimeError("stubbed error")
    }
}
