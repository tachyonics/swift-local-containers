import Foundation
import LocalContainers
import Testing

@testable import ContainerizationRuntime

@Suite("ContainerizationManager — qualifyImageReference")
struct QualifyImageReferenceTests {
    private let manager = ContainerizationManager()

    @Test("Simple name gets docker.io/library/ prefix")
    func simpleName() async {
        let result = await manager.qualifyImageReference("nginx")
        #expect(result == "docker.io/library/nginx")
    }

    @Test("Simple name with tag gets docker.io/library/ prefix")
    func simpleNameWithTag() async {
        let result = await manager.qualifyImageReference("nginx:latest")
        #expect(result == "docker.io/library/nginx:latest")
    }

    @Test("Simple name with specific tag")
    func simpleNameWithSpecificTag() async {
        let result = await manager.qualifyImageReference("alpine:3.19")
        #expect(result == "docker.io/library/alpine:3.19")
    }

    @Test("Namespaced image gets docker.io/ prefix")
    func namespacedImage() async {
        let result = await manager.qualifyImageReference("localstack/localstack:latest")
        #expect(result == "docker.io/localstack/localstack:latest")
    }

    @Test("Namespaced image without tag")
    func namespacedWithoutTag() async {
        let result = await manager.qualifyImageReference("localstack/localstack")
        #expect(result == "docker.io/localstack/localstack")
    }

    @Test("Fully qualified registry with dot is unchanged")
    func fullyQualifiedWithDot() async {
        let result = await manager.qualifyImageReference("ghcr.io/org/image:v1")
        #expect(result == "ghcr.io/org/image:v1")
    }

    @Test("Registry with port is unchanged")
    func registryWithPort() async {
        let result = await manager.qualifyImageReference("localhost:5000/myimage:latest")
        #expect(result == "localhost:5000/myimage:latest")
    }

    @Test("Localhost registry is unchanged")
    func localhostRegistry() async {
        let result = await manager.qualifyImageReference("localhost/myimage:v2")
        #expect(result == "localhost/myimage:v2")
    }

    @Test("docker.io explicit reference is unchanged")
    func dockerIoExplicit() async {
        let result = await manager.qualifyImageReference("docker.io/library/nginx:latest")
        #expect(result == "docker.io/library/nginx:latest")
    }
}

@Suite("ContainerizationManager — resolvePortMappings")
struct ResolvePortMappingsTests {
    private let manager = ContainerizationManager()

    @Test("Port with no host port uses container port as host port")
    func noHostPort() async {
        let result = await manager.resolvePortMappings(
            from: [PortMapping(containerPort: 8080)]
        )
        #expect(result.count == 1)
        #expect(result[0].containerPort == 8080)
        #expect(result[0].hostPort == 8080)
    }

    @Test("Port with explicit host port preserves it")
    func explicitHostPort() async {
        let result = await manager.resolvePortMappings(
            from: [PortMapping(containerPort: 80, hostPort: 8080)]
        )
        #expect(result.count == 1)
        #expect(result[0].containerPort == 80)
        #expect(result[0].hostPort == 8080)
    }

    @Test("Multiple ports are all resolved")
    func multiplePorts() async {
        let result = await manager.resolvePortMappings(
            from: [
                PortMapping(containerPort: 80),
                PortMapping(containerPort: 443, hostPort: 8443),
            ]
        )
        #expect(result.count == 2)
        #expect(result[0].hostPort == 80)
        #expect(result[1].hostPort == 8443)
    }

    @Test("Empty ports returns empty result")
    func emptyPorts() async {
        let result = await manager.resolvePortMappings(from: [])
        #expect(result.isEmpty)
    }

    @Test("UDP protocol is preserved")
    func udpProtocol() async {
        let result = await manager.resolvePortMappings(
            from: [PortMapping(containerPort: 53, protocol: .udp)]
        )
        #expect(result[0].protocol == .udp)
    }
}

@Suite("ContainerizationManager — inspect and logs for absent containers")
struct AbsentContainerTests {
    private let manager = ContainerizationManager()

    @Test("inspect returns not-running for unknown container ID")
    func inspectUnknown() async {
        let inspection = await manager.inspect(containerID: "nonexistent")
        #expect(inspection.isRunning == false)
        #expect(inspection.status == "exited")
    }

    @Test("logs returns empty string for unknown container ID")
    func logsUnknown() async throws {
        let logs = try await manager.logs(containerID: "nonexistent")
        #expect(logs.isEmpty)
    }
}
