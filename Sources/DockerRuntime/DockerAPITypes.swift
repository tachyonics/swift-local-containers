/// Codable types matching the Docker Engine API JSON structures.
///
/// Names follow Docker's conventions to minimise custom `CodingKeys`.

// MARK: - Create Container

public struct CreateContainerRequest: Codable, Sendable {
    public var Image: String
    public var Env: [String]?
    public var Cmd: [String]?
    public var ExposedPorts: [String: EmptyObject]?
    public var HostConfig: HostConfig?
    public var Healthcheck: Healthcheck?

    public init(
        Image: String,
        Env: [String]? = nil,
        Cmd: [String]? = nil,
        ExposedPorts: [String: EmptyObject]? = nil,
        HostConfig: HostConfig? = nil,
        Healthcheck: Healthcheck? = nil
    ) {
        self.Image = Image
        self.Env = Env
        self.Cmd = Cmd
        self.ExposedPorts = ExposedPorts
        self.HostConfig = HostConfig
        self.Healthcheck = Healthcheck
    }
}

public struct EmptyObject: Codable, Sendable {
    public init() {}
}

public struct HostConfig: Codable, Sendable {
    public var PortBindings: [String: [PortBinding]]?
    public var Binds: [String]?

    public init(
        PortBindings: [String: [PortBinding]]? = nil,
        Binds: [String]? = nil
    ) {
        self.PortBindings = PortBindings
        self.Binds = Binds
    }
}

public struct PortBinding: Codable, Sendable {
    public var HostIp: String?
    public var HostPort: String?

    public init(HostIp: String? = nil, HostPort: String? = nil) {
        self.HostIp = HostIp
        self.HostPort = HostPort
    }
}

public struct Healthcheck: Codable, Sendable {
    public var Test: [String]?
    public var Interval: Int?
    public var Timeout: Int?
    public var Retries: Int?
    public var StartPeriod: Int?

    public init(
        Test: [String]? = nil,
        Interval: Int? = nil,
        Timeout: Int? = nil,
        Retries: Int? = nil,
        StartPeriod: Int? = nil
    ) {
        self.Test = Test
        self.Interval = Interval
        self.Timeout = Timeout
        self.Retries = Retries
        self.StartPeriod = StartPeriod
    }
}

public struct CreateContainerResponse: Codable, Sendable {
    public var Id: String
    public var Warnings: [String]?
}

// MARK: - Inspect Container

public struct InspectContainerResponse: Codable, Sendable {
    public var Id: String
    public var Name: String
    public var State: ContainerState
    public var NetworkSettings: NetworkSettings

    public struct ContainerState: Codable, Sendable {
        public var Status: String
        public var Running: Bool
        public var Health: HealthState?
    }

    public struct HealthState: Codable, Sendable {
        public var Status: String
    }

    public struct NetworkSettings: Codable, Sendable {
        public var Ports: [String: [PortMapping]?]?

        public struct PortMapping: Codable, Sendable {
            public var HostIp: String?
            public var HostPort: String?
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
