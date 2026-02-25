import Smockable
import Testing

@testable import LocalContainers
@testable import PlatformRuntime

@Smock(additionalEquatableTypes: [RunningContainer.self])
protocol TestContainerRuntime: ContainerRuntime {
    func pullImage(_ reference: String) async throws
    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer
    func stopContainer(_ container: RunningContainer) async throws
    func removeContainer(_ container: RunningContainer) async throws
    func inspect(container: RunningContainer) async throws -> ContainerInspection
    func logs(for container: RunningContainer) async throws -> String
}

private let stubbedContainer = RunningContainer(
    id: "stub-1",
    name: "stub",
    image: "stub:latest",
    ports: [ResolvedPortMapping(containerPort: 80, hostPort: 32000)]
)

private func makeMock() -> MockTestContainerRuntime {
    var expectations = MockTestContainerRuntime.Expectations()
    when(expectations.pullImage(.any), complete: .withSuccess)
    when(expectations.startContainer(from: .any), return: stubbedContainer)
    when(expectations.stopContainer(.any), complete: .withSuccess)
    when(expectations.removeContainer(.any), complete: .withSuccess)
    when(
        expectations.inspect(container: .any),
        return: ContainerInspection(isRunning: true, healthStatus: .healthy)
    )
    when(expectations.logs(for: .any), return: "")
    return MockTestContainerRuntime(expectations: expectations)
}

@Suite("PlatformRuntime")
struct PlatformRuntimeTests {
    @Test("pullImage delegates to underlying runtime")
    func pullDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)

        try await runtime.pullImage("nginx:latest")

        verify(mock).pullImage("nginx:latest")
    }

    @Test("startContainer delegates and returns the result")
    func startDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)

        let config = ContainerConfiguration(image: "redis:7")
        let container = try await runtime.startContainer(from: config)

        verify(mock).startContainer(from: .matching { $0.image == "redis:7" })
        #expect(container.id == "stub-1")
    }

    @Test("stopContainer delegates to underlying runtime")
    func stopDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)
        let container = RunningContainer(id: "c-1", name: "test", image: "test")

        try await runtime.stopContainer(container)

        verify(mock).stopContainer(container)
    }

    @Test("removeContainer delegates to underlying runtime")
    func removeDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)
        let container = RunningContainer(id: "c-2", name: "test", image: "test")

        try await runtime.removeContainer(container)

        verify(mock).removeContainer(container)
    }

    @Test("inspectContainer delegates to underlying runtime")
    func inspectDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)
        let container = RunningContainer(id: "c-3", name: "test", image: "test")

        let inspection = try await runtime.inspect(container: container)

        verify(mock).inspect(container: container)
        #expect(inspection.isRunning == true)
        #expect(inspection.healthStatus == .healthy)
    }

    @Test("containerLogs delegates to underlying runtime")
    func logsDelegation() async throws {
        let mock = makeMock()
        let runtime = PlatformRuntime(runtime: mock)
        let container = RunningContainer(id: "c-4", name: "test", image: "test")

        let logs = try await runtime.logs(for: container)

        verify(mock).logs(for: container)
        #expect(logs == "")
    }

    @Test("Errors from underlying runtime propagate")
    func errorPropagation() async {
        var expectations = MockTestContainerRuntime.Expectations()
        when(
            expectations.pullImage(.any),
            throw: ContainerError.imagePullFailed(image: "bad:image", reason: "stubbed error")
        )
        let mock = MockTestContainerRuntime(expectations: expectations)
        let runtime = PlatformRuntime(runtime: mock)

        await #expect(throws: ContainerError.self) {
            try await runtime.pullImage("bad:image")
        }
    }
}
