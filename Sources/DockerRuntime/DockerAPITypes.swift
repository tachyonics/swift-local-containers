// Codable types matching the Docker Engine API JSON structures.
//
// Properties use Swift naming conventions; `CodingKeys` map to Docker's JSON keys.

// MARK: - Create Container

package struct CreateContainerRequest: Codable, Sendable {
    package var image: String
    package var env: [String]?
    package var cmd: [String]?
    package var exposedPorts: [String: EmptyObject]?
    package var hostConfig: HostConfig?
    package var healthcheck: Healthcheck?

    package init(
        image: String,
        env: [String]? = nil,
        cmd: [String]? = nil,
        exposedPorts: [String: EmptyObject]? = nil,
        hostConfig: HostConfig? = nil,
        healthcheck: Healthcheck? = nil
    ) {
        self.image = image
        self.env = env
        self.cmd = cmd
        self.exposedPorts = exposedPorts
        self.hostConfig = hostConfig
        self.healthcheck = healthcheck
    }

    private enum CodingKeys: String, CodingKey {
        case image = "Image"
        case env = "Env"
        case cmd = "Cmd"
        case exposedPorts = "ExposedPorts"
        case hostConfig = "HostConfig"
        case healthcheck = "Healthcheck"
    }
}

package struct EmptyObject: Codable, Sendable {
    package init() {}
}

package struct HostConfig: Codable, Sendable {
    package var portBindings: [String: [PortBinding]]?
    package var binds: [String]?

    package init(
        portBindings: [String: [PortBinding]]? = nil,
        binds: [String]? = nil
    ) {
        self.portBindings = portBindings
        self.binds = binds
    }

    private enum CodingKeys: String, CodingKey {
        case portBindings = "PortBindings"
        case binds = "Binds"
    }
}

package struct PortBinding: Codable, Sendable {
    package var hostIp: String?
    package var hostPort: String?

    package init(hostIp: String? = nil, hostPort: String? = nil) {
        self.hostIp = hostIp
        self.hostPort = hostPort
    }

    private enum CodingKeys: String, CodingKey {
        case hostIp = "HostIp"
        case hostPort = "HostPort"
    }
}

package struct Healthcheck: Codable, Sendable {
    package var test: [String]?
    package var interval: Int?
    package var timeout: Int?
    package var retries: Int?
    package var startPeriod: Int?

    package init(
        test: [String]? = nil,
        interval: Int? = nil,
        timeout: Int? = nil,
        retries: Int? = nil,
        startPeriod: Int? = nil
    ) {
        self.test = test
        self.interval = interval
        self.timeout = timeout
        self.retries = retries
        self.startPeriod = startPeriod
    }

    private enum CodingKeys: String, CodingKey {
        case test = "Test"
        case interval = "Interval"
        case timeout = "Timeout"
        case retries = "Retries"
        case startPeriod = "StartPeriod"
    }
}

package struct CreateContainerResponse: Codable, Sendable {
    package var id: String
    package var warnings: [String]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case warnings = "Warnings"
    }
}

// MARK: - Inspect Container

package struct InspectContainerResponse: Codable, Sendable {
    package var id: String
    package var name: String
    package var state: InspectContainerState
    package var networkSettings: InspectNetworkSettings

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case state = "State"
        case networkSettings = "NetworkSettings"
    }
}

package struct InspectContainerState: Codable, Sendable {
    package var status: String
    package var running: Bool
    package var health: InspectHealthState?

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case running = "Running"
        case health = "Health"
    }
}

package struct InspectHealthState: Codable, Sendable {
    package var status: String

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
    }
}

package struct InspectNetworkSettings: Codable, Sendable {
    package var ports: [String: [InspectPortMapping]?]?
    package var gateway: String?
    package var networks: [String: InspectNetworkInfo]?

    private enum CodingKeys: String, CodingKey {
        case ports = "Ports"
        case gateway = "Gateway"
        case networks = "Networks"
    }
}

package struct InspectPortMapping: Codable, Sendable {
    package var hostIp: String?
    package var hostPort: String?

    private enum CodingKeys: String, CodingKey {
        case hostIp = "HostIp"
        case hostPort = "HostPort"
    }
}

package struct InspectNetworkInfo: Codable, Sendable {
    package var gateway: String?

    private enum CodingKeys: String, CodingKey {
        case gateway = "Gateway"
    }
}

// MARK: - Pull Image

package struct PullImageProgress: Codable, Sendable {
    package var status: String?
    package var id: String?
    package var progress: String?
    package var error: String?
}
