import AsyncHTTPClient
import Foundation
import LocalContainers
import NIOCore

extension GenericDockerAPIClient {
    /// Build an image from a tarred build context.
    ///
    /// The Engine API streams build progress as NDJSON. A 200 status alone is
    /// not enough to declare success — the stream may carry an `{"error": ...}`
    /// line. We drain the stream and surface any error as `imageBuildFailed`.
    package func buildImage(
        contextTar: Data,
        dockerfile: String,
        tag: String
    ) async throws {
        logger.info(
            "Building image",
            metadata: ["tag": "\(tag)", "dockerfile": "\(dockerfile)"]
        )

        let url = try apiURL(
            "/build",
            query: [
                ("t", tag),
                ("dockerfile", dockerfile),
                ("rm", "1")
            ]
        )

        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/x-tar")
        request.headers.add(name: "Host", value: "localhost")
        request.body = .bytes(contextTar)

        let response = try await executor.execute(
            request,
            timeout: .seconds(600),
            logger: nil
        )

        guard (200..<300).contains(Int(response.status.code)) else {
            throw ContainerError.imageBuildFailed(
                tag: tag,
                reason: "HTTP \(response.status.code)"
            )
        }

        if let lastError = try await drainBuildStream(response.body) {
            throw ContainerError.imageBuildFailed(tag: tag, reason: lastError)
        }
    }

    /// Inspect an image by reference and return its metadata.
    package func inspectImage(reference: String) async throws -> ImageInspection {
        logger.info("Inspecting image", metadata: ["reference": "\(reference)"])

        let url = try apiURL("/images/\(reference)/json")
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        request.headers.add(name: "Host", value: "localhost")

        let response = try await executor.execute(request, timeout: .seconds(30), logger: nil)
        var body = try await response.body.collect(upTo: Self.maxResponseSize)

        if response.status.code == 404 {
            throw ContainerError.imageNotFound(reference: reference)
        }
        guard (200..<300).contains(Int(response.status.code)) else {
            let message = extractErrorMessage(from: &body) ?? "HTTP \(response.status.code)"
            throw ContainerError.runtimeError(message)
        }

        let decoded = try JSONDecoder().decode(InspectImageResponse.self, from: body)
        return Self.mapImageInspection(decoded)
    }

    static func mapImageInspection(_ response: InspectImageResponse) -> ImageInspection {
        let exposed: [ExposedPort] = (response.config.exposedPorts ?? [:]).keys
            .compactMap { key in
                let parts = key.split(separator: "/", maxSplits: 1)
                guard let port = UInt16(parts[0]) else { return nil }
                let proto: TransportProtocol =
                    (parts.count == 2 && parts[1] == "udp") ? .udp : .tcp
                return ExposedPort(port: port, protocol: proto)
            }
            .sorted { ($0.port, $0.protocol.rawValue) < ($1.port, $1.protocol.rawValue) }
        return ImageInspection(id: response.id, exposedPorts: exposed)
    }

    /// Drain the NDJSON build response stream, returning the last `error` line if any.
    private func drainBuildStream(
        _ body: HTTPClientResponse.Body
    ) async throws -> String? {
        var buffer = ByteBuffer()
        let decoder = JSONDecoder()
        var lastError: String?

        for try await chunk in body {
            var chunk = chunk
            buffer.writeBuffer(&chunk)
            while let line = readLine(from: &buffer) {
                lastError = handleBuildLine(line, decoder: decoder, fallback: lastError)
            }
        }
        if let trailing = buffer.readString(length: buffer.readableBytes) {
            lastError = handleBuildLine(trailing, decoder: decoder, fallback: lastError)
        }
        return lastError
    }

    private func handleBuildLine(
        _ line: String,
        decoder: JSONDecoder,
        fallback: String?
    ) -> String? {
        guard let progress = decodeProgress(line, decoder: decoder) else { return fallback }
        if let error = progress.error, !error.isEmpty {
            return error
        }
        if let stream = progress.stream {
            let trimmed = stream.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logger.debug("docker build", metadata: ["stream": "\(trimmed)"])
            }
        }
        return fallback
    }

    private func readLine(from buffer: inout ByteBuffer) -> String? {
        let view = buffer.readableBytesView
        guard let newlineIdx = view.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let length = newlineIdx - view.startIndex + 1
        return buffer.readString(length: length)
    }

    private func decodeProgress(
        _ line: String,
        decoder: JSONDecoder
    ) -> BuildImageProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? decoder.decode(BuildImageProgress.self, from: Data(trimmed.utf8))
    }
}
