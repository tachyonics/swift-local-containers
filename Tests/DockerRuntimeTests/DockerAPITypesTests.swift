import Foundation
import Testing

@testable import DockerRuntime

@Suite("DockerAPITypes")
struct DockerAPITypesTests {
    @Test("CreateContainerRequest encodes to expected JSON")
    func encodeCreateRequest() throws {
        let request = CreateContainerRequest(
            Image: "nginx:latest",
            Env: ["FOO=bar"],
            ExposedPorts: ["80/tcp": EmptyObject()],
            HostConfig: HostConfig(
                PortBindings: ["80/tcp": [PortBinding(HostIp: "0.0.0.0", HostPort: "8080")]]
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

        #expect(response.Id == "abc123def456")
        #expect(response.Warnings?.isEmpty == true)
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

        #expect(response.Id == "abc123")
        #expect(response.State.Running == true)
        #expect(response.NetworkSettings.Ports?["80/tcp"]??.count == 1)
        #expect(response.NetworkSettings.Ports?["80/tcp"]??[0].HostPort == "32768")
    }

    @Test("DockerPortResolver resolves ports from inspect response")
    func portResolution() {
        let networkSettings = InspectContainerResponse.NetworkSettings(
            Ports: [
                "8080/tcp": [
                    InspectContainerResponse.NetworkSettings.PortMapping(
                        HostIp: "0.0.0.0",
                        HostPort: "32768"
                    )
                ],
                "53/udp": [
                    InspectContainerResponse.NetworkSettings.PortMapping(
                        HostIp: "0.0.0.0",
                        HostPort: "32769"
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
private struct AnyCodable: Codable {
    let value: Any

    var stringValue: String? { value as? String }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = "unknown"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        }
    }
}
