import AsyncHTTPClient
import Foundation
import LocalContainers
import NIOCore

extension GenericDockerAPIClient {
    /// Inspect an image by reference and return its metadata.
    ///
    /// Used to discover declared `EXPOSE` ports for service-container port auto-mapping.
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
        return mapImageInspection(decoded)
    }
}

func mapImageInspection(_ response: InspectImageResponse) -> ImageInspection {
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
