import Foundation
import PackagePlugin

/// Build plugin that generates typed `StackOutputs` structs from
/// CloudFormation templates listed in `.local-containers/codegen.json`
/// at the package root.
///
/// Each entry in the manifest's `templates[]` declares a source template
/// file (path relative to the target's source directory) and the exact
/// name of the generated struct. The plugin emits one build command per
/// entry whose `source` resolves to an existing file under the current
/// target — this is how manifest entries are implicitly scoped to the
/// target they belong to, without the user having to declare the target.
///
/// If the manifest is absent, the plugin emits no build commands. There
/// is no fallback "scan any .json for AWSTemplateFormatVersion" behavior.
@main
struct ContainerCodeGenPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let manifestURL =
            context.package.directoryURL
            .appendingPathComponent(".local-containers")
            .appendingPathComponent("codegen.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return []
        }

        let manifest = try loadManifest(at: manifestURL)
        let tool = try context.tool(named: "ContainerCodeGenTool")
        let outputDir = context.pluginWorkDirectoryURL
        let targetRoot = sourceTarget.directoryURL

        var commands: [Command] = []

        for entry in manifest.templates ?? [] {
            let templateURL = targetRoot.appending(path: entry.source)
            guard FileManager.default.fileExists(atPath: templateURL.path) else {
                // Entry belongs to a different target.
                continue
            }

            let outputFile = outputDir.appending(path: "\(entry.structName).swift")
            // The tool also writes a copy of the template into the plugin
            // work directory. The generated struct's `templatePath` computed
            // property resolves to this file via `#filePath` at compile time.
            let stagedTemplate = outputDir.appending(
                path: "\(entry.structName).template.json"
            )

            commands.append(
                .buildCommand(
                    displayName:
                        "Generate \(entry.structName) from \(templateURL.lastPathComponent)",
                    executable: tool.url,
                    arguments: [
                        "template",
                        templateURL.path(percentEncoded: false),
                        outputFile.path(percentEncoded: false),
                        entry.structName,
                    ],
                    inputFiles: [templateURL],
                    outputFiles: [outputFile, stagedTemplate]
                )
            )
        }

        for entry in manifest.cdkapps ?? [] {
            let cdkAppURL = targetRoot.appending(path: entry.source)
            guard
                FileManager.default.fileExists(atPath: cdkAppURL.path)
            else {
                // Entry belongs to a different target.
                continue
            }

            let outputFile = outputDir.appending(path: "\(entry.structName).swift")
            let stagedTemplate = outputDir.appending(
                path: "\(entry.structName).template.json"
            )

            // Collect the CDK app's source files as build inputs so SPM
            // re-runs synth when they change. Skips node_modules and cdk.out
            // to avoid ballooning the input set.
            let inputs = collectCDKAppInputs(at: cdkAppURL)

            commands.append(
                .buildCommand(
                    displayName:
                        "Synthesize CDK app \(entry.source) -> \(entry.structName)",
                    executable: tool.url,
                    arguments: [
                        "cdk-synth",
                        cdkAppURL.path(percentEncoded: false),
                        entry.stackName,
                        outputFile.path(percentEncoded: false),
                        entry.structName,
                    ],
                    inputFiles: inputs,
                    outputFiles: [outputFile, stagedTemplate]
                )
            )
        }

        return commands
    }

    /// Enumerates files under the CDK app directory, excluding `node_modules`
    /// and `cdk.out`. Used as the input-file set for the synth build command
    /// so SPM tracks re-synth correctness.
    private func collectCDKAppInputs(at cdkAppURL: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: cdkAppURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var results: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            let components = item.pathComponents
            if components.contains("node_modules") || components.contains("cdk.out") {
                enumerator.skipDescendants()
                continue
            }
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                results.append(item)
            }
        }
        return results
    }

    // MARK: - Manifest

    private func loadManifest(at url: URL) throws -> CodegenManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodegenManifest.self, from: data)
    }
}

// MARK: - Manifest Schema

private struct CodegenManifest: Decodable {
    let templates: [TemplateEntry]?
    let cdkapps: [CDKAppEntry]?
}

private struct TemplateEntry: Decodable {
    let source: String
    let structName: String
}

private struct CDKAppEntry: Decodable {
    let source: String
    let stackName: String
    let structName: String
}
