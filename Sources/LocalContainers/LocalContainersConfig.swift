import Foundation

/// Loads project-local **secret** configuration from `.local-containers/env`
/// in the current working directory.
///
/// This file is expected to be gitignored — it holds tokens and overrides
/// that should not be committed (e.g. `LOCALSTACK_AUTH_TOKEN`). For shared,
/// committed configuration (log level, etc.), see ``LocalContainersSettings``.
///
/// The file uses a simple `KEY=VALUE` syntax (one pair per line). Blank
/// lines and lines beginning with `#` are ignored. Surrounding single or
/// double quotes are stripped from values.
///
/// Values are exposed via ``values`` and ``value(for:)`` — they are
/// read only from the file, never from the process environment. Callers
/// are responsible for deciding precedence when merging with other
/// sources (e.g. via
/// `LocalStackContainer.environmentForwarding(merging:)`).
///
/// Intended layout:
/// ```
/// .local-containers/
///     env                  # gitignored — secrets and local overrides
///     config               # committed — shared library settings
/// ```
public enum LocalContainersConfig {
    /// Relative path to the env file from the current working directory.
    public static let relativePath = ".local-containers/env"

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

/// Internal helper shared by ``LocalContainersConfig`` and
/// ``LocalContainersSettings``. Reads a `KEY=VALUE` config file from disk
/// and parses it into a dictionary.
enum KeyValueFileLoader {
    /// Reads and parses a config file at the given URL. Returns an empty
    /// dictionary if the file does not exist or cannot be read.
    static func load(from url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for (key, value) in parse(contents) {
            result[key] = value
        }
        return result
    }

    /// Parses `KEY=VALUE` lines. Blank lines and `#` comments are skipped;
    /// surrounding single/double quotes are stripped from values.
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
            if value.count >= 2, let first = value.first, let last = value.last,
                (first == "\"" && last == "\"") || (first == "'" && last == "'")
            {
                value = String(value.dropFirst().dropLast())
            }
            result.append((key, value))
        }
        return result
    }
}
