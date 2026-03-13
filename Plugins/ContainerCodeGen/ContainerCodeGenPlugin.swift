import Foundation
import PackagePlugin

@main
struct ContainerCodeGenPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        let tool = try context.tool(named: "ContainerCodeGenTool")
        let outputDir = context.pluginWorkDirectoryURL

        // Find JSON files that are CloudFormation templates
        let jsonFiles = sourceTarget.sourceFiles(withSuffix: ".json").map(\.url)
        let templateFiles = jsonFiles.filter { isCloudFormationTemplate(at: $0) }

        var commands: [Command] = []
        for templateFile in templateFiles {
            let stem = templateFile.deletingPathExtension().lastPathComponent
            let outputFile = outputDir.appending(path: "\(pascalCase(stem))Outputs.swift")

            commands.append(
                .buildCommand(
                    displayName: "Generate StackOutputs for \(templateFile.lastPathComponent)",
                    executable: tool.url,
                    arguments: [
                        templateFile.path(percentEncoded: false),
                        outputFile.path(percentEncoded: false),
                    ],
                    inputFiles: [templateFile],
                    outputFiles: [outputFile]
                )
            )
        }

        return commands
    }
}

private func isCloudFormationTemplate(at url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return false
    }
    return json["AWSTemplateFormatVersion"] != nil
}

private func pascalCase(_ string: String) -> String {
    string
        .split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined()
}
