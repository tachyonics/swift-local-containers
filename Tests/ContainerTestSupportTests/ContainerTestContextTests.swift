import Foundation
import Smockable
import Testing

@testable import ContainerTestSupport
@testable import LocalContainers

@Smock(additionalEquatableTypes: [RunningContainer.self])
protocol TestContainerRuntime: ContainerRuntime {
    func pullImage(_ reference: String) async throws
    func buildImage(contextTar: Data, dockerfile: String, tag: String) async throws
    func inspectImage(reference: String) async throws -> ImageInspection
    func startContainer(from configuration: ContainerConfiguration) async throws -> RunningContainer
    func stopContainer(_ container: RunningContainer) async throws
    func removeContainer(_ container: RunningContainer) async throws
    func exec(command: [String], in container: RunningContainer) async throws -> Int32
    func inspect(container: RunningContainer) async throws -> ContainerInspection
    func logs(for container: RunningContainer) async throws -> String
}

// MARK: - SharedContainerManager Tests

private enum SharedTestKey: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(
            image: "test:latest",
            waitStrategy: .custom { _ in }
        )
    )
}

@Suite("SharedContainerManager")
struct SharedContainerManagerTests {
    @Test("container(for:runtime:) starts container and executes wait strategy")
    func containerStartsWithWait() async throws {
        let stubbedContainer = RunningContainer(
            id: "stub-1",
            name: "stub",
            image: "test:latest"
        )
        var expectations = MockTestContainerRuntime.Expectations()
        when(expectations.pullImage(.any), complete: .withSuccess)
        when(expectations.startContainer(from: .any), return: stubbedContainer)
        when(expectations.stopContainer(.any), complete: .withSuccess)
        when(expectations.removeContainer(.any), complete: .withSuccess)
        let mock = MockTestContainerRuntime(expectations: expectations)

        let container = try await SharedContainerManager.shared.container(
            for: SharedTestKey.self,
            runtime: mock
        )

        verify(mock).pullImage("test:latest")
        verify(mock).startContainer(from: .matching { $0.image == "test:latest" })
        #expect(container.id == "stub-1")
    }
}

// MARK: - Container Keys

private struct FakeDB: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "postgres:16", ports: [PortMapping(containerPort: 5432)])
    )
}

private struct FakeCache: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "redis:7", ports: [PortMapping(containerPort: 6379)])
    )
}

private struct Unregistered: ContainerKey {
    static let spec = ContainerSpec(
        ContainerConfiguration(image: "nginx:latest")
    )
}

@Suite("ContainerTestContext")
struct ContainerTestContextTests {
    private static let dbContainer = RunningContainer(
        id: "pg-1",
        name: "postgres",
        image: "postgres:16",
        ports: [ResolvedPortMapping(containerPort: 5432, hostPort: 54320)]
    )

    private static let cacheContainer = RunningContainer(
        id: "redis-1",
        name: "redis",
        image: "redis:7",
        ports: [ResolvedPortMapping(containerPort: 6379, hostPort: 63790)]
    )

    @Test("Subscript returns the correct container for a key")
    func lookupByKey() throws {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer,
            ObjectIdentifier(FakeCache.self): Self.cacheContainer,
        ])

        let db = try ctx[FakeDB.self]
        #expect(db.id == "pg-1")
        #expect(db.image == "postgres:16")

        let cache = try ctx[FakeCache.self]
        #expect(cache.id == "redis-1")
    }

    @Test("Subscript throws for an unregistered key")
    func lookupMissingKey() {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer
        ])

        #expect(throws: ContainerError.self) {
            try ctx[Unregistered.self]
        }
    }

    @Test("Empty context throws for any lookup")
    func emptyContext() {
        let ctx = ContainerTestContext(containers: [:])

        #expect(throws: ContainerError.self) {
            try ctx[FakeDB.self]
        }
    }

    @Test("TaskLocal current is nil by default")
    func taskLocalDefault() {
        #expect(ContainerTestContext.current == nil)
    }

    @Test("TaskLocal current is set within withValue scope")
    func taskLocalWithValue() async {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer
        ])

        ContainerTestContext.$current.withValue(ctx) {
            let current = ContainerTestContext.current
            #expect(current != nil)
            let db = try? current?[FakeDB.self]
            #expect(db?.id == "pg-1")
        }

        #expect(ContainerTestContext.current == nil)
    }

    // MARK: - outputs(for:)

    @Test("outputs(for:) returns stored stack outputs")
    func outputsForKey() {
        let expected = ["BucketName": "my-bucket", "QueueUrl": "http://localhost/queue"]
        let ctx = ContainerTestContext(
            containers: [ObjectIdentifier(FakeDB.self): Self.dbContainer],
            stackOutputs: [ObjectIdentifier(FakeDB.self): expected]
        )

        let outputs = ctx.outputs(for: ObjectIdentifier(FakeDB.self))
        #expect(outputs == expected)
    }

    @Test("outputs(for:) returns nil for unregistered key")
    func outputsForMissingKey() {
        let ctx = ContainerTestContext(
            containers: [ObjectIdentifier(FakeDB.self): Self.dbContainer]
        )

        let outputs = ctx.outputs(for: ObjectIdentifier(Unregistered.self))
        #expect(outputs == nil)
    }

    // MARK: - output(for:)

    @Test("output(for:) returns stored typed output")
    func typedOutputForKey() {
        let expectedOutput = "typed-value"
        let ctx = ContainerTestContext(
            containers: [ObjectIdentifier(FakeDB.self): Self.dbContainer],
            typedOutputs: [ObjectIdentifier(FakeDB.self): expectedOutput]
        )

        let result: String? = ctx.output(for: ObjectIdentifier(FakeDB.self))
        #expect(result == "typed-value")
    }

    @Test("output(for:) returns nil for unregistered key")
    func typedOutputForMissingKey() {
        let ctx = ContainerTestContext(
            containers: [ObjectIdentifier(FakeDB.self): Self.dbContainer]
        )

        let result: String? = ctx.output(for: ObjectIdentifier(Unregistered.self))
        #expect(result == nil)
    }

    @Test("output(for:) returns nil for type mismatch")
    func typedOutputTypeMismatch() {
        let ctx = ContainerTestContext(
            containers: [ObjectIdentifier(FakeDB.self): Self.dbContainer],
            typedOutputs: [ObjectIdentifier(FakeDB.self): "a string"]
        )

        let result: Int? = ctx.output(for: ObjectIdentifier(FakeDB.self))
        #expect(result == nil)
    }

    // MARK: - ErasedContainerKey outputConstructor

    @Test("ErasedContainerKey stores and invokes outputConstructor")
    func erasedKeyOutputConstructor() throws {
        let key = ErasedContainerKey(
            FakeDB.self,
            outputConstructor: { rawOutputs in
                rawOutputs["key"] ?? "missing"
            }
        )

        #expect(key.outputConstructor != nil)
        let result = try key.outputConstructor?(["key": "value"])
        #expect(result as? String == "value")
    }

    @Test("ErasedContainerKey outputConstructor defaults to nil")
    func erasedKeyNoOutputConstructor() {
        let key = ErasedContainerKey(FakeDB.self)
        #expect(key.outputConstructor == nil)
    }

    // MARK: - requireCurrent()

    @Test("requireCurrent() throws when no context is set")
    func requireCurrentThrows() {
        #expect(throws: ContainerError.self) {
            try ContainerTestContext.requireCurrent()
        }
    }

    @Test("requireCurrent() returns context within withValue scope")
    func requireCurrentReturns() {
        let ctx = ContainerTestContext(containers: [
            ObjectIdentifier(FakeDB.self): Self.dbContainer
        ])

        ContainerTestContext.$current.withValue(ctx) {
            let current = try? ContainerTestContext.requireCurrent()
            #expect(current != nil)
            let db = try? current?[FakeDB.self]
            #expect(db?.id == "pg-1")
        }
    }
}
