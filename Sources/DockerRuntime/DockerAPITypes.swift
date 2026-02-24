/// Codable types matching the Docker Engine API JSON structures.
///
/// Properties use Swift naming conventions; `CodingKeys` map to Docker's JSON keys.

// MARK: - Create Container

public struct CreateContainerRequest: Codable, Sendable {
    public var image: String
    public var env: [String]?
    public var cmd: [String]?
    public var exposedPorts: [String: EmptyObject]?
    public var hostConfig: HostConfig?
    public var healthcheck: Healthcheck?

    public init(
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

public struct EmptyObject: Codable, Sendable {
    public init() {}
}

public struct HostConfig: Codable, Sendable {
    public var portBindings: [String: [PortBinding]]?
    public var binds: [String]?

    public init(
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

public struct PortBinding: Codable, Sendable {
    public var hostIp: String?
    public var hostPort: String?

    public init(hostIp: String? = nil, hostPort: String? = nil) {
        self.hostIp = hostIp
        self.hostPort = hostPort
    }

    private enum CodingKeys: String, CodingKey {
        case hostIp = "HostIp"
        case hostPort = "HostPort"
    }
}

public struct Healthcheck: Codable, Sendable {
    public var test: [String]?
    public var interval: Int?
    public var timeout: Int?
    public var retries: Int?
    public var startPeriod: Int?

    public init(
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

public struct CreateContainerResponse: Codable, Sendable {
    public var id: String
    public var warnings: [String]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case warnings = "Warnings"
    }
}

// MARK: - Inspect Container

public struct InspectContainerResponse: Codable, Sendable {
    public var id: String
    public var name: String
    public var state: ContainerState
    public var networkSettings: NetworkSettings

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case state = "State"
        case networkSettings = "NetworkSettings"
    }

    public struct ContainerState: Codable, Sendable {
        public var status: String
        public var running: Bool
        public var health: HealthState?

        private enum CodingKeys: String, CodingKey {
            case status = "Status"
            case running = "Running"
            case health = "Health"
        }
    }

    public struct HealthState: Codable, Sendable {
        public var status: String

        private enum CodingKeys: String, CodingKey {
            case status = "Status"
        }
    }

    public struct NetworkSettings: Codable, Sendable {
        public var ports: [String: [PortMapping]?]?
        public var gateway: String?
        public var networks: [String: NetworkInfo]?

        private enum CodingKeys: String, CodingKey {
            case ports = "Ports"
            case gateway = "Gateway"
            case networks = "Networks"
        }

        public struct PortMapping: Codable, Sendable {
            public var hostIp: String?
            public var hostPort: String?

            private enum CodingKeys: String, CodingKey {
                case hostIp = "HostIp"
                case hostPort = "HostPort"
            }
        }

        public struct NetworkInfo: Codable, Sendable {
            public var gateway: String?

            private enum CodingKeys: String, CodingKey {
                case gateway = "Gateway"
            }
        }
    }
}

// MARK: - Pull Image

public struct PullImageProgress: Codable, Sendable {
    public var status: String?
    public var id: String?
    public var progress: String?
    public var error: String?
}
