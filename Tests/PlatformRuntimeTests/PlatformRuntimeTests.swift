import Testing

@testable import LocalContainers
@testable import PlatformRuntime

private final class StubContainerRuntime: ContainerRuntime, @unchecked Sendable {
    var pulledImages: [String] = []
    var startedConfigs: [ContainerConfiguration] = []
    var stoppedIDs: [String] = []
    var removedIDs: [String] = []

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
}

@Suite("PlatformRuntime")
struct PlatformRuntimeTests {
    @Test("pullImage delegates to underlying runtime")
    func pullDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)

        try await runtime.pullImage("nginx:latest")

        #expect(stub.pulledImages == ["nginx:latest"])
    }

    @Test("startContainer delegates and returns the result")
    func startDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)

        let config = ContainerConfiguration(image: "redis:7")
        let container = try await runtime.startContainer(from: config)

        #expect(stub.startedConfigs.count == 1)
        #expect(stub.startedConfigs[0].image == "redis:7")
        #expect(container.id == "stub-1")
    }

    @Test("stopContainer delegates to underlying runtime")
    func stopDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-1", name: "test", image: "test")

        try await runtime.stopContainer(container)

        #expect(stub.stoppedIDs == ["c-1"])
    }

    @Test("removeContainer delegates to underlying runtime")
    func removeDelegation() async throws {
        let stub = StubContainerRuntime()
        let runtime = PlatformRuntime(runtime: stub)
        let container = RunningContainer(id: "c-2", name: "test", image: "test")

        try await runtime.removeContainer(container)

        #expect(stub.removedIDs == ["c-2"])
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
}
