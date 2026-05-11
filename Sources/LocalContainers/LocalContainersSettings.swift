import Foundation

/// Loads project-local **committed** settings from `.local-containers/config`
/// in the current working directory.
///
/// This file is intended to live in source control — it holds shared
/// configuration the whole team uses (log level, default timeouts, etc.).
/// Secrets and per-developer overrides belong in `.local-containers/env`,
/// loaded by ``LocalContainersConfig``.
///
/// File format is the same KEY=VALUE syntax as `env`: one pair per line,
/// blank lines and `#` comments ignored, surrounding quotes stripped.
public enum LocalContainersSettings {
    /// Relative path to the config file from the current working directory.
    public static let relativePath = ".local-containers/config"

    /// All key/value pairs loaded from the config file. Empty if the file
    /// does not exist.
    public static var values: [String: String] { loaded }

    /// Look up a single value from the config file.
    public static func value(for key: String) -> String? {
        loaded[key]
    }

    private static let loaded: [String: String] = {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(relativePath)
        return KeyValueFileLoader.load(from: url)
    }()
}
