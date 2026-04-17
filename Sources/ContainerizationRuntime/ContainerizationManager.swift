import Containerization
import Foundation
import LocalContainers
import Logging

/// Manages VM and image resources for the Containerization backend.
///
/// Owns the ``ContainerManager``, ``ImageStore``, running ``LinuxContainer``
/// instances, and per-container log writers. All mutable state is isolated
/// inside this actor.
actor ContainerizationManager {
    private let logger: Logger
    private let imageStore: ImageStore
    private var containerManager: ContainerManager?
    private var runningContainers: [String: LinuxContainer] = [:]
    private var stdoutWriters: [String: LogAccumulatingWriter] = [:]
    private var stderrWriters: [String: LogAccumulatingWriter] = [:]

    init(logger: Logger = Logger(label: "ContainerizationManager")) {
        self.logger = logger
        self.imageStore = .default
    }

    // MARK: - Image management

    func pullImage(_ reference: String) async throws {
        let qualified = qualifyImageReference(reference)
        _ = try await imageStore.get(reference: qualified, pull: true)
    }

    // MARK: - Container lifecycle

    struct StartResult: Sendable {
        let containerID: String
        let name: String
        let host: String
        let ports: [ResolvedPortMapping]
    }

    @available(macOS 26.0, *)
    func startContainer(
        from configuration: ContainerConfiguration
    ) async throws -> StartResult {
        var manager = try await ensureManager()

        let containerID = configuration.name ?? UUID().uuidString
        let stdoutWriter = LogAccumulatingWriter()
        let stderrWriter = LogAccumulatingWriter()
        let containerConfig = configuration

        let qualifiedImage = qualifyImageReference(containerConfig.image)
        let container = try await manager.create(
            containerID,
            reference: qualifiedImage
        ) { config in
            if let command = containerConfig.command {
                config.process.arguments = command
            }
            for (key, value) in containerConfig.environment {
                config.process.environmentVariables.append("\(key)=\(value)")
            }
            config.process.stdout = stdoutWriter
            config.process.stderr = stderrWriter
            for volume in containerConfig.volumes {
                var options: [String] = []
                if volume.readOnly {
                    options.append("ro")
                }
                config.mounts.append(
                    .share(
                        source: volume.hostPath,
                        destination: volume.containerPath,
                        options: options
                    )
                )
            }
        }

        self.containerManager = manager

        try await container.create()
        try await container.start()

        let host = extractContainerIPAddress(from: container)
        let resolvedPorts = resolvePortMappings(from: configuration.ports)

        runningContainers[containerID] = container
        stdoutWriters[containerID] = stdoutWriter
        stderrWriters[containerID] = stderrWriter

        logger.info(
            "Container started",
            metadata: ["id": "\(containerID)", "host": "\(host)"]
        )

        return StartResult(
            containerID: containerID,
            name: containerID,
            host: host,
            ports: resolvedPorts
        )
    }

    func stopContainer(identifier: String) async throws {
        guard let container = runningContainers[identifier] else {
            throw ContainerError.containerNotFound(id: identifier)
        }
        try await container.stop()
        logger.info("Container stopped", metadata: ["id": "\(identifier)"])
    }

    func removeContainer(identifier: String) async throws {
        if runningContainers[identifier] != nil {
            try? await stopContainer(identifier: identifier)
        }
        if var manager = containerManager {
            try manager.delete(identifier)
            self.containerManager = manager
        }
        runningContainers.removeValue(forKey: identifier)
        stdoutWriters.removeValue(forKey: identifier)
        stderrWriters.removeValue(forKey: identifier)
        logger.info("Container removed", metadata: ["id": "\(identifier)"])
    }

    func inspect(containerID: String) -> ContainerInspection {
        let isRunning = runningContainers[containerID] != nil
        return ContainerInspection(
            isRunning: isRunning,
            status: isRunning ? "running" : "exited"
        )
    }

    func execCommand(
        _ command: [String],
        containerID: String
    ) async throws -> Int32 {
        guard let container = runningContainers[containerID] else {
            throw ContainerError.containerNotFound(id: containerID)
        }
        let execID = UUID().uuidString
        let process = try await container.exec(execID) { config in
            config.arguments = command
        }
        try await process.start()
        let exitStatus = try await process.wait()
        try await process.delete()
        return exitStatus.exitCode
    }

    func logs(containerID: String) throws -> String {
        let stdout = stdoutWriters[containerID]?.contents() ?? ""
        let stderr = stderrWriters[containerID]?.contents() ?? ""
        if stderr.isEmpty {
            return stdout
        }
        if stdout.isEmpty {
            return stderr
        }
        return stdout + stderr
    }

    // MARK: - Private helpers

    @available(macOS 26.0, *)
    private func ensureManager() async throws -> ContainerManager {
        if let manager = containerManager {
            return manager
        }
        let kernel = try resolveKernel()
        let network = try VmnetNetwork()
        let manager = try await ContainerManager(
            kernel: kernel,
            initfsReference: "vminit:latest",
            imageStore: imageStore,
            network: network
        )
        self.containerManager = manager
        return manager
    }

    private func resolveKernel() throws -> Kernel {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let kernelsDir =
            homeDir
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.apple.container/kernels")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: kernelsDir.path) else {
            throw ContainerError.runtimeError(
                "Linux kernel not found. Install with: `brew install container`"
            )
        }

        let contents = try fileManager.contentsOfDirectory(
            at: kernelsDir,
            includingPropertiesForKeys: nil
        )
        let kernelFiles =
            contents
            .filter { $0.lastPathComponent.hasPrefix("vmlinux-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard let kernelPath = kernelFiles.first else {
            throw ContainerError.runtimeError(
                "Linux kernel not found. Install with: `brew install container`"
            )
        }

        return Kernel(path: kernelPath, platform: .linuxArm)
    }

    func resolvePortMappings(
        from ports: [PortMapping]
    ) -> [ResolvedPortMapping] {
        ports.map { mapping in
            ResolvedPortMapping(
                containerPort: mapping.containerPort,
                hostPort: mapping.hostPort ?? mapping.containerPort,
                protocol: mapping.protocol
            )
        }
    }

    private func extractContainerIPAddress(
        from container: LinuxContainer
    ) -> String {
        container.interfaces.first?.ipv4Address.address.description
            ?? "127.0.0.1"
    }

    /// Qualifies a short Docker Hub reference into a fully-qualified form.
    ///
    /// The Containerization framework requires an explicit registry domain.
    /// - `"nginx:latest"` → `"docker.io/library/nginx:latest"`
    /// - `"localstack/localstack:latest"` → `"docker.io/localstack/localstack:latest"`
    /// - `"ghcr.io/org/image:v1"` → unchanged (already qualified)
    func qualifyImageReference(_ reference: String) -> String {
        let domainSeparator = reference.firstIndex(of: "/")

        guard let separatorIndex = domainSeparator else {
            // No slash at all — single name like "nginx" or "nginx:latest"
            return "docker.io/library/\(reference)"
        }

        let domainCandidate = reference[reference.startIndex..<separatorIndex]
        let looksLikeDomain =
            domainCandidate.contains(".")
            || domainCandidate.contains(":")
            || domainCandidate == "localhost"

        if looksLikeDomain {
            return reference
        }

        // Has a slash but no domain — e.g. "localstack/localstack:latest"
        return "docker.io/\(reference)"
    }
}
