import LocalContainers

/// Resolves Docker inspect response port mappings into ``ResolvedPortMapping`` values.
public enum DockerPortResolver {
    /// Parse the `NetworkSettings.Ports` dictionary from a Docker inspect response
    /// into an array of ``ResolvedPortMapping``.
    public static func resolve(
        from networkSettings: InspectContainerResponse.NetworkSettings
    ) -> [ResolvedPortMapping] {
        guard let portMap = networkSettings.ports else { return [] }

        var resolved: [ResolvedPortMapping] = []

        for (key, bindings) in portMap {
            guard let bindings else { continue }
            let (containerPort, proto) = parsePortKey(key)
            guard let containerPort else { continue }

            for binding in bindings {
                guard let hostPortString = binding.hostPort,
                    let hostPort = UInt16(hostPortString)
                else { continue }

                resolved.append(
                    ResolvedPortMapping(
                        containerPort: containerPort,
                        hostPort: hostPort,
                        protocol: proto
                    )
                )
            }
        }

        return resolved
    }

    /// Parse a Docker port key like `"8080/tcp"` into a port number and protocol.
    private static func parsePortKey(_ key: String) -> (UInt16?, TransportProtocol) {
        let parts = key.split(separator: "/")
        let port = parts.first.flatMap { UInt16($0) }
        let proto: TransportProtocol = parts.count > 1 && parts[1] == "udp" ? .udp : .tcp
        return (port, proto)
    }
}
