import Foundation
import PackagePlugin

/// Command plugin that performs one-time setup operations for every
/// category declared in `.local-containers/codegen.json` that cannot run
/// under SwiftPM's build sandbox.
///
/// Today there is one category — CDK apps (`cdkapps[]`) — for which the
/// plugin runs `npm install` inside each declared CDK app directory. The
/// plugin is deliberately named generically so future categories (e.g.
/// Docker image pre-pulls, Python virtualenvs, etc.) can be added as
/// additional handler blocks below without introducing a separate command
/// per category. Users invoke a single `bootstrap` command regardless of
/// what they've declared.
///
/// ## Why a command plugin
///
/// The `ContainerCodeGen` build tool plugin runs under SwiftPM's build
/// sandbox, which denies network access and restricts filesystem writes.
/// That's correct for a build plugin, but it means `npm install` — or
/// anything else that needs the network — can't run there. Command
/// plugins, in contrast, can declare explicit permissions
/// (`.allowNetworkConnections`, `.writeToPackageDirectory`) and the user
/// opts in by passing the matching flags. The tradeoff is that command
/// plugins don't run automatically as part of `swift build` — users
/// invoke them explicitly, which is exactly what we want for one-time
/// setup.
///
/// ## Usage
///
///     swift package --allow-network-connections all \
///                   --allow-writing-to-package-directory bootstrap
///
/// In CI, add this as one extra step before `swift test`:
///
///     - name: Bootstrap
///       run: swift package --allow-network-connections all \
///                          --allow-writing-to-package-directory bootstrap
///     - name: Run tests
///       run: swift test
@main
struct BootstrapPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let manifestURL =
            context.package.directoryURL
            .appendingPathComponent(".local-containers")
            .appendingPathComponent("codegen.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            print(
                "bootstrap: no .local-containers/codegen.json found — nothing to do."
            )
            return
        }

        let manifest = try loadManifest(at: manifestURL)
        let sourceTargets = context.package.targets.compactMap {
            $0 as? SourceModuleTarget
        }

        var totalProcessed = 0
        var totalSkipped = 0

        // MARK: CDK apps handler
        //
        // Iterates `cdkapps[]` entries from the manifest, resolves each
        // against every source module target (implicit target scoping to
        // match the ContainerCodeGen build plugin), and runs `npm install`
        // in the resolved directory to populate `node_modules/.bin/cdk`.
        let cdkResult = try bootstrapCDKApps(
            entries: manifest.cdkapps ?? [],
            sourceTargets: sourceTargets
        )
        totalProcessed += cdkResult.processed
        totalSkipped += cdkResult.skipped

        // Future handler blocks slot in here. Each should:
        //   - Read a category-specific section from the manifest
        //   - Resolve paths against sourceTargets for implicit scoping
        //   - Run whatever external tool it needs (with network/write
        //     permissions already granted to the command plugin)
        //   - Return a BootstrapResult for the summary
        //
        // Examples: dockerimages[] (docker pull), pythonenvs[] (virtualenv
        // + pip install -r), etc.

        if totalProcessed == 0 && totalSkipped == 0 {
            print("bootstrap: nothing declared in any handler — nothing to do.")
        } else {
            print(
                "bootstrap: done (processed \(totalProcessed), skipped \(totalSkipped))"
            )
        }
    }

    // MARK: - CDK Apps

    private func bootstrapCDKApps(
        entries: [CDKAppEntry],
        sourceTargets: [SourceModuleTarget]
    ) throws -> BootstrapResult {
        var processed = 0
        var skipped = 0

        for entry in entries {
            guard let cdkAppURL = resolve(source: entry.source, in: sourceTargets) else {
                print(
                    "bootstrap: warning: cdkapps entry \"\(entry.source)\" does not exist under any target source directory — skipping"
                )
                skipped += 1
                continue
            }

            print("bootstrap: installing dependencies in \(cdkAppURL.path)")
            try runNpmInstall(at: cdkAppURL)
            processed += 1
        }

        return BootstrapResult(processed: processed, skipped: skipped)
    }

    private func runNpmInstall(at cdkAppURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "install", "--no-audit", "--no-fund"]
        process.currentDirectoryURL = cdkAppURL

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw BootstrapError.npmInstallFailed(
                directory: cdkAppURL.path,
                status: process.terminationStatus
            )
        }
    }

    // MARK: - Path resolution

    /// Resolves a manifest entry's `source` path against every source
    /// module target in the package. Returns the first absolute URL that
    /// exists on disk, or `nil` if the path doesn't resolve anywhere.
    /// Mirrors the implicit target-scoping used by the ContainerCodeGen
    /// build plugin.
    private func resolve(
        source: String,
        in targets: [SourceModuleTarget]
    ) -> URL? {
        for target in targets {
            let candidate = target.directoryURL.appending(path: source)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Manifest

    private func loadManifest(at url: URL) throws -> CodegenManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodegenManifest.self, from: data)
    }
}

// MARK: - Manifest Schema
//
// Kept in sync with the ContainerCodeGen build plugin by convention —
// if one changes, update both. Only the sections this plugin actually
// handles are decoded.

private struct CodegenManifest: Decodable {
    let cdkapps: [CDKAppEntry]?
}

private struct CDKAppEntry: Decodable {
    let source: String
    let stackName: String
    let structName: String
}

// MARK: - Result & Errors

private struct BootstrapResult {
    let processed: Int
    let skipped: Int
}

private enum BootstrapError: Error, CustomStringConvertible {
    case npmInstallFailed(directory: String, status: Int32)

    var description: String {
        switch self {
        case .npmInstallFailed(let directory, let status):
            return "npm install failed in \(directory) with status \(status)"
        }
    }
}
