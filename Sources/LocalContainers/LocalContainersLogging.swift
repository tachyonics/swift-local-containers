import Foundation
import Logging

/// Global log-level configuration for swift-local-containers internal loggers.
///
/// Every logger constructed by the library (DockerContainerRuntime, the wait
/// strategy executor, container traits, LocalStack helpers, …) reads its
/// level from `level`, which is sourced from
/// `.local-containers/config`'s `LOCAL_CONTAINERS_LOG_LEVEL` key. Defaults
/// to `.info` when the key is unset or unrecognized.
///
/// The settings file is intended to be committed to source control so the
/// whole team shares the same log level. Secrets (e.g. LOCALSTACK_AUTH_TOKEN)
/// belong in the separate gitignored `.local-containers/env` file.
///
/// Recognized values (case-insensitive): `trace`, `debug`, `info`, `notice`,
/// `warning`, `error`, `critical`.
///
/// Users who supply their own `Logger` to component initializers (e.g.
/// `DockerContainerRuntime(logger:)`) override this — the global level only
/// applies to library-created loggers.
public enum LocalContainersLogging {
    static let settingsKey = "LOCAL_CONTAINERS_LOG_LEVEL"

    /// Log level applied to all swift-local-containers internal loggers.
    public static var level: Logger.Level { resolved }

    private static let resolved: Logger.Level = {
        guard let raw = LocalContainersSettings.value(for: settingsKey) else {
            return .info
        }
        return parse(raw) ?? .info
    }()

    /// Construct a logger with `label` at the configured global level.
    /// Internal call site for default loggers across the library.
    public static func makeLogger(label: String) -> Logger {
        var logger = Logger(label: label)
        logger.logLevel = level
        return logger
    }

    /// Parse a `Logger.Level` from its swift-log string spelling.
    /// Case-insensitive. Exposed for testing.
    static func parse(_ raw: String) -> Logger.Level? {
        switch raw.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "notice": return .notice
        case "warning": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return nil
        }
    }
}
