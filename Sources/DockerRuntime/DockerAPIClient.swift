import AsyncHTTPClient
import Foundation
import LocalContainers
import Logging
import NIOCore
import NIOFoundationCompat

/// HTTP client for the Docker Engine API over a Unix domain socket.
package struct GenericDockerAPIClient<Executor: HTTPExecutor>: Sendable {
    private let socketPath: String
    private let logger: Logger
    private let executor: Executor

    private static var apiVersion: String { "v1.47" }
    private static var maxResponseSize: Int { 10 * 1024 * 1024 }  // 10 MB

    init(
        socketPath: String = "/var/run/docker.sock",
        logger: Logger = Logger(label: "DockerAPIClient"),
        executor: Executor
    ) {
        self.socketPath = socketPath
        self.logger = logger
        self.executor = executor
    }

    /// Pull an image by reference.
    package func pullImage(_ reference: String) async throws {
        logger.info("Pulling image", metadata: ["image": "\(reference)"])

        let (image, tag) = Self.parseImageReference(reference)
        let url = try apiURL("/images/create", query: [("fromImage", image), ("tag", tag)])

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Host", value: "localhost")

        let response = try await executor.execute(
            request,
            timeout: .seconds(300),
            logger: nil
        )

        // Pull returns an NDJSON stream — consume it line by line checking for errors
        var body = try await response.body.collect(upTo: Self.maxResponseSize)
        let decoder = JSONDecoder()

        while body.readableBytes > 0 {
            guard
                let line = body.readString(
                    length: body.readableBytesView.firstIndex(of: UInt8(ascii: "\n")).map {
                        $0 - body.readableBytesView.startIndex + 1
                    } ?? body.readableBytes
                )
            else {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let progress = try? decoder.decode(PullImageProgress.self, from: Data(trimmed.utf8)) {
                if let error = progress.error, !error.isEmpty {
                    throw ContainerError.imagePullFailed(image: reference, reason: error)
                }
            }
        }

        guard (200..<300).contains(Int(response.status.code)) else {
            throw ContainerError.imagePullFailed(
                image: reference,
                reason: "HTTP \(response.status.code)"
            )
        }
    }

    /// Create a container from the given request body.
    package func createContainer(
        _ request: CreateContainerRequest,
        name: String? = nil
    ) async throws -> CreateContainerResponse {
        logger.info("Creating container", metadata: ["image": "\(request.image)"])

        var query: [(String, String)] = []
        if let name {
            query.append(("name", name))
        }

        let url = try apiURL("/containers/create", query: query)
        var httpRequest = HTTPClientRequest(url: url)
        httpRequest.method = .POST
        httpRequest.headers.add(name: "Content-Type", value: "application/json")
        httpRequest.headers.add(name: "Host", value: "localhost")

        let body = try JSONEncoder().encode(request)
        httpRequest.body = .bytes(body)

        let responseBody = try await executeRequest(httpRequest)
        return try JSONDecoder().decode(CreateContainerResponse.self, from: responseBody)
    }

    /// Start a created container.
    package func startContainer(id: String) async throws {
        logger.info("Starting container", metadata: ["id": "\(id)"])

        let url = try apiURL("/containers/\(id)/start")
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Host", value: "localhost")

        // 204 = success, 304 = already started
        _ = try await executeRequest(request, acceptableStatuses: [304])
    }

    /// Inspect a running container.
    package func inspectContainer(id: String) async throws -> InspectContainerResponse {
        logger.info("Inspecting container", metadata: ["id": "\(id)"])

        let url = try apiURL("/containers/\(id)/json")
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Host", value: "localhost")

        let body = try await executeRequest(request)
        return try JSONDecoder().decode(InspectContainerResponse.self, from: body)
    }

    /// Stop a running container.
    package func stopContainer(id: String, timeout: Int = 10) async throws {
        logger.info("Stopping container", metadata: ["id": "\(id)"])

        let url = try apiURL("/containers/\(id)/stop", query: [("t", String(timeout))])
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Host", value: "localhost")

        // 204 = success, 304 = already stopped
        _ = try await executeRequest(request, acceptableStatuses: [304])
    }

    /// Fetch logs from a container.
    ///
    /// Docker returns a multiplexed stream when TTY is disabled — each frame has
    /// an 8-byte header (`[stream_type, 0, 0, 0, size_be32]`) followed by payload bytes.
    /// When TTY is enabled, the response is plain text with no framing.
    package func containerLogs(id: String) async throws -> String {
        logger.info("Fetching container logs", metadata: ["id": "\(id)"])

        let url = try apiURL(
            "/containers/\(id)/logs",
            query: [("stdout", "1"), ("stderr", "1")]
        )
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Host", value: "localhost")

        let body = try await executeRequest(request)
        return Self.demultiplexDockerLogs(body)
    }

    /// Remove a container.
    package func removeContainer(id: String, force: Bool = false) async throws {
        logger.info("Removing container", metadata: ["id": "\(id)"])

        let url = try apiURL("/containers/\(id)", query: [("force", String(force))])
        var request = HTTPClientRequest(url: url)
        request.method = .DELETE
        request.headers.add(name: "Host", value: "localhost")

        _ = try await executeRequest(request)
    }

    // MARK: - Private Helpers

    /// Builds a URL string for the Docker API using the Unix socket path.
    private func apiURL(
        _ path: String,
        query: [(String, String)] = []
    ) throws -> String {
        let fullPath = "/\(Self.apiVersion)\(path)"

        var components = URLComponents()
        components.path = fullPath
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }

        guard let uri = components.string else {
            throw ContainerError.runtimeError("Failed to construct API URL for \(path)")
        }

        guard
            let url = URL(
                httpURLWithSocketPath: socketPath,
                uri: uri
            )
        else {
            throw ContainerError.runtimeError("Failed to construct API URL for \(path)")
        }
        return url.absoluteString
    }

    /// Sends an HTTP request and collects the response body.
    /// Throws `ContainerError` for non-2xx status codes (unless in `acceptableStatuses`).
    private func executeRequest(
        _ request: HTTPClientRequest,
        acceptableStatuses: Set<UInt> = [],
        timeout: TimeAmount = .seconds(30)
    ) async throws -> ByteBuffer {
        let response = try await executor.execute(request, timeout: timeout, logger: nil)

        var body = try await response.body.collect(upTo: Self.maxResponseSize)

        let status = UInt(response.status.code)
        guard (200..<300).contains(Int(status)) || acceptableStatuses.contains(status) else {
            // Try to extract Docker's error message
            let message =
                extractErrorMessage(from: &body)
                ?? "HTTP \(status)"

            if status == 404 {
                // Try to determine if this is a container not found
                let url = request.url
                if url.contains("/containers/") {
                    let components = url.split(separator: "/")
                    if let containerIdx = components.firstIndex(of: "containers"),
                        containerIdx + 1 < components.endIndex
                    {
                        let id = String(components[containerIdx + 1])
                        throw ContainerError.containerNotFound(id: id)
                    }
                }
            }

            throw ContainerError.runtimeError(message)
        }

        return body
    }

    /// Attempts to extract an error message from the Docker API's JSON error response.
    private func extractErrorMessage(from body: inout ByteBuffer) -> String? {
        (try? JSONDecoder().decode(DockerErrorResponse.self, from: body))?.message
    }

    /// Splits an image reference into (image, tag).
    ///
    /// Handles references like:
    /// - `"nginx"` → `("nginx", "latest")`
    /// - `"nginx:1.25"` → `("nginx", "1.25")`
    /// - `"localstack/localstack:3.0"` → `("localstack/localstack", "3.0")`
    /// - `"registry:5000/myimage"` → `("registry:5000/myimage", "latest")`
    /// Demultiplexes Docker log output.
    ///
    /// When TTY is disabled, Docker prefixes each frame with an 8-byte header:
    /// `[stream_type(1), padding(3), size_big_endian(4)]` followed by `size` payload bytes.
    /// When TTY is enabled the response is plain text with no framing.
    ///
    /// This method detects the format and returns a plain UTF-8 string.
    static func demultiplexDockerLogs(_ buffer: ByteBuffer) -> String {
        var buf = buffer
        guard buf.readableBytes >= 8 else {
            return String(buffer: buf)
        }

        // Peek at the first byte — Docker stream types are 0 (stdin), 1 (stdout), 2 (stderr).
        // If the first byte isn't one of these, treat as plain text (TTY mode).
        guard let firstByte = buf.getInteger(at: buf.readerIndex, as: UInt8.self),
            firstByte <= 2
        else {
            return String(buffer: buf)
        }

        var output = ""
        while buf.readableBytes >= 8 {
            // Read stream type (1 byte) + 3 padding bytes
            guard let header = buf.readInteger(as: UInt32.self) else { break }
            let streamType = UInt8(header >> 24)
            // Validate stream type
            guard streamType <= 2 else {
                // Not a valid multiplexed stream, treat remainder as plain text
                buf.moveReaderIndex(to: buf.readerIndex - 4)
                output += String(buffer: buf)
                return output
            }

            // Read frame size (4 bytes, big endian)
            guard let frameSize = buf.readInteger(as: UInt32.self) else { break }
            let size = Int(frameSize)

            guard size > 0, buf.readableBytes >= size else { break }
            if let payload = buf.readString(length: size) {
                output += payload
            } else {
                buf.moveReaderIndex(forwardBy: size)
            }
        }

        // Append any trailing bytes
        if buf.readableBytes > 0 {
            output += String(buffer: buf)
        }

        return output
    }

    static func parseImageReference(_ reference: String) -> (image: String, tag: String) {
        guard let colonIndex = reference.lastIndex(of: ":") else {
            return (reference, "latest")
        }

        let afterColon = reference[reference.index(after: colonIndex)...]
        // If the part after the last colon contains a slash, it's a registry port, not a tag
        if afterColon.contains("/") {
            return (reference, "latest")
        }

        let image = String(reference[..<colonIndex])
        let tag = String(afterColon)
        return (image, tag)
    }
}

extension GenericDockerAPIClient where Executor == HTTPClient {
    /// Creates a client connecting to the Docker daemon at the given Unix socket.
    ///
    /// - Parameter socketPath: Path to the Docker socket. Defaults to `/var/run/docker.sock`.
    package init(
        socketPath: String = "/var/run/docker.sock",
        logger: Logger = Logger(label: "DockerAPIClient")
    ) {
        self.socketPath = socketPath
        self.logger = logger
        self.executor = .shared
    }
}

/// Default `DockerAPIClient` backed by `HTTPClient`.
package typealias DockerAPIClient = GenericDockerAPIClient<HTTPClient>

private struct DockerErrorResponse: Codable {
    var message: String
}
