import Foundation
import Testing

@testable import DockerRuntime

@Suite("DockerAPITypes")
struct DockerAPITypesTests {
    @Test("CreateContainerRequest encodes to expected JSON")
    func encodeCreateRequest() throws {
        let request = CreateContainerRequest(
            image: "nginx:latest",
            env: ["FOO=bar"],
            exposedPorts: ["80/tcp": EmptyObject()],
            hostConfig: HostConfig(
                portBindings: ["80/tcp": [PortBinding(hostIp: "0.0.0.0", hostPort: "8080")]]
            )
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        #expect(json["Image"]?.stringValue == "nginx:latest")
    }

    @Test("CreateContainerResponse decodes from JSON")
    func decodeCreateResponse() throws {
        let json = """
            {"Id":"abc123def456","Warnings":[]}
            """
        let response = try JSONDecoder().decode(
            CreateContainerResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.id == "abc123def456")
        #expect(response.warnings?.isEmpty == true)
    }

    @Test("InspectContainerResponse decodes port mappings")
    func decodeInspectResponse() throws {
        let json = """
            {
                "Id": "abc123",
                "Name": "/test-container",
                "State": {
                    "Status": "running",
                    "Running": true
                },
                "NetworkSettings": {
                    "Ports": {
                        "80/tcp": [{"HostIp": "0.0.0.0", "HostPort": "32768"}],
                        "443/tcp": null
                    }
                }
            }
            """
        let response = try JSONDecoder().decode(
            InspectContainerResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.id == "abc123")
        #expect(response.state.running == true)
        #expect(response.networkSettings.ports?["80/tcp"]??.count == 1)
        #expect(response.networkSettings.ports?["80/tcp"]??[0].hostPort == "32768")
    }

    @Test("DockerPortResolver resolves ports from inspect response")
    func portResolution() {
        let networkSettings = InspectContainerResponse.NetworkSettings(
            ports: [
                "8080/tcp": [
                    InspectContainerResponse.NetworkSettings.PortMapping(
                        hostIp: "0.0.0.0",
                        hostPort: "32768"
                    )
                ],
                "53/udp": [
                    InspectContainerResponse.NetworkSettings.PortMapping(
                        hostIp: "0.0.0.0",
                        hostPort: "32769"
                    )
                ],
                "9090/tcp": nil,
            ]
        )

        let resolved = DockerPortResolver.resolve(from: networkSettings)

        #expect(resolved.count == 2)

        let tcp = resolved.first { $0.containerPort == 8080 }
        #expect(tcp?.hostPort == 32768)
        #expect(tcp?.protocol == .tcp)

        let udp = resolved.first { $0.containerPort == 53 }
        #expect(udp?.hostPort == 32769)
        #expect(udp?.protocol == .udp)
    }
}

// Minimal AnyCodable for JSON round-trip verification
private struct AnyCodable: Codable, Sendable {
    let stringValue: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            stringValue = string
        } else {
            stringValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = stringValue {
            try container.encode(string)
        }
    }
}
