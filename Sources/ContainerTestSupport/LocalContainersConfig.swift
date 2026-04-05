import Foundation

/// Loads project-local test configuration from `.local-containers/env`
/// in the current working directory.
///
/// The file uses a simple `KEY=VALUE` syntax (one pair per line). Blank
/// lines and lines beginning with `#` are ignored. Surrounding single or
/// double quotes are stripped from values.
///
/// Values are exposed via ``values`` and ``value(for:)`` — they are
/// *not* injected into the process environment. Callers pass them
/// explicitly where needed (e.g. via
/// `LocalStackContainer(environment:)`).
///
/// Intended layout:
/// ```
/// .local-containers/
///     env                  # gitignored — secrets and overrides
///     config.toml          # (future) committed shared config
/// ```
public enum LocalContainersConfig {
    /// Relative path to the env file from the current working directory.
    public static let relativePath = ".local-containers/env"

    /// All key/value pairs loaded from the config file. Empty if the file
    /// does not exist. Real environment variables always take precedence,
    /// so any key already present in the process environment replaces the
    /// value from the file.
    public static var values: [String: String] { loaded }

    /// Look up a single value, falling back to the process environment.
    public static func value(for key: String) -> String? {
        if let fromEnv = ProcessInfo.processInfo.environment[key], !fromEnv.isEmpty {
            return fromEnv
        }
        return loaded[key]
    }

    private static let loaded: [String: String] = {
        let cwd = FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: cwd).appendingPathComponent(relativePath)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in parse(contents) {
            // Real env vars win; don't override them from the file.
            if ProcessInfo.processInfo.environment[key] == nil {
                result[key] = value
            }
        }
        return result
    }()

    /// Parses `KEY=VALUE` lines. Exposed for testing.
    static func parse(_ contents: String) -> [(key: String, value: String)] {
        var result: [(String, String)] = []
        for rawLine in contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                let first = value.first!
                let last = value.last!
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            result.append((key, value))
        }
        return result
    }
}
