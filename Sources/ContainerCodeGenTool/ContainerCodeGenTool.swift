import Foundation

@main
enum ContainerCodeGenTool {
    /// Maps CloudFormation resource type prefixes to LocalStack service names.
    private static let serviceMapping: [String: String] = [
        "AWS::S3::": "s3",
        "AWS::SQS::": "sqs",
        "AWS::SNS::": "sns",
        "AWS::DynamoDB::": "dynamodb",
        "AWS::Lambda::": "lambda",
        "AWS::IAM::": "iam",
        "AWS::Events::": "events",
        "AWS::StepFunctions::": "stepfunctions",
        "AWS::Kinesis::": "kinesis",
        "AWS::SecretsManager::": "secretsmanager",
        "AWS::SSM::": "ssm",
    ]

    /// Marker string indicating the template was synthesized by CDK's
    /// `DefaultStackSynthesizer` — template references this SSM parameter
    /// to look up the installed CDK bootstrap version. When we see this
    /// marker we implicitly add `"ssm"` to the required LocalStack services
    /// so the runtime stub has a service to talk to.
    private static let cdkBootstrapMarker = "/cdk-bootstrap/hnb659fds/version"

    static func main() {
        // Every throw site inside `run(...)` writes a helpful message to
        // stderr before throwing, so we swallow the error here and exit
        // with a non-zero status. This avoids Swift's runtime appending
        // the "Fatal error: Error raised at top level" trailer to what
        // would otherwise be clean, actionable user-facing output.
        do {
            try run()
        } catch {
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            writeStderr(usage)
            throw ExitError.badUsage
        }

        let subcommand = arguments[1]
        let tail = Array(arguments.dropFirst(2))

        switch subcommand {
        case "template":
            try runTemplate(tail)
        case "cdk-synth":
            try runCDKSynth(tail)
        default:
            writeStderr("Unknown subcommand: \(subcommand)")
            writeStderr(usage)
            throw ExitError.badUsage
        }
    }

    private static let usage = """
        Usage:
          ContainerCodeGenTool template <template.json> <output.swift> <struct-name>
          ContainerCodeGenTool cdk-synth <cdk-app-dir> <stack-name> <output.swift> <struct-name>
        """

    // MARK: - Subcommand: template

    private static func runTemplate(_ arguments: [String]) throws {
        guard arguments.count == 3 else {
            writeStderr(usage)
            throw ExitError.badUsage
        }

        let templatePath = arguments[0]
        let outputPath = arguments[1]
        let typeName = arguments[2]

        try generate(
            fromTemplate: URL(fileURLWithPath: templatePath),
            outputPath: outputPath,
            typeName: typeName
        )
    }

    // MARK: - Subcommand: cdk-synth

    private static func runCDKSynth(_ arguments: [String]) throws {
        guard arguments.count == 4 else {
            writeStderr(usage)
            throw ExitError.badUsage
        }

        let cdkAppPath = arguments[0]
        let stackName = arguments[1]
        let outputPath = arguments[2]
        let typeName = arguments[3]

        let cdkAppURL = URL(fileURLWithPath: cdkAppPath)

        try verifyCDKDependenciesInstalled(at: cdkAppURL)

        let synthOutputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdk-synth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: synthOutputDir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: synthOutputDir) }

        try runCDKSynthCommand(
            cdkAppURL: cdkAppURL,
            stackName: stackName,
            outputDir: synthOutputDir
        )

        let synthesizedTemplate =
            synthOutputDir
            .appendingPathComponent("\(stackName).template.json")

        guard FileManager.default.fileExists(atPath: synthesizedTemplate.path) else {
            writeStderr(
                "cdk synth completed but template not found at \(synthesizedTemplate.path)"
            )
            throw ExitError.invalidTemplate
        }

        try generate(
            fromTemplate: synthesizedTemplate,
            outputPath: outputPath,
            typeName: typeName
        )
    }

    /// Message appended to subprocess failures when the error looks like a
    /// missing `npm`/`npx` on PATH (exit status 127 from `/usr/bin/env`, or
    /// "No such file or directory" in stderr). Helps users understand they
    /// probably need to invoke `swift build` from a shell where their Node
    /// install is on PATH.
    private static let pathHelp = """
        Hint: this usually means `npm`/`npx` isn't on PATH in the environment \
        that launched `swift build`. If Node is installed via nvm/fnm/volta or \
        another version manager, make sure your shell has activated it before \
        running the build (try running `which npx` in the same shell you use \
        for `swift build` — if it fails there, the plugin won't find it either).
        """

    private static func looksLikeMissingCommand(
        status: Int32,
        stderr: String
    ) -> Bool {
        status == 127 || stderr.contains("No such file or directory")
    }

    /// Verifies the `cdk` CLI binary is present at `node_modules/.bin/cdk`
    /// in the CDK app directory. Does NOT run `npm install` — SwiftPM's
    /// build-plugin sandbox denies network access, so that would always
    /// fail here. Seeding `node_modules` is the job of the `bootstrap`
    /// command plugin (`swift package bootstrap`), which runs outside
    /// the build sandbox with explicit network permission.
    ///
    /// When the marker is missing, emits a clear error pointing users at
    /// the bootstrap command.
    private static func verifyCDKDependenciesInstalled(at cdkAppURL: URL) throws {
        let marker =
            cdkAppURL
            .appendingPathComponent("node_modules")
            .appendingPathComponent(".bin")
            .appendingPathComponent("cdk")
        if FileManager.default.fileExists(atPath: marker.path) {
            return
        }

        writeStderr(
            """
            CDK dependencies are not installed in \(cdkAppURL.path).
            The build tool plugin runs under SwiftPM's build sandbox and \
            cannot reach the npm registry itself.

            Run the bootstrap command plugin once before building:

              swift package --allow-network-connections all \\
                            --allow-writing-to-package-directory bootstrap

            This installs node_modules (including the `cdk` CLI) for every \
            cdkapps[] entry in .local-containers/codegen.json. After that, \
            `swift build` / `swift test` will synthesize offline.
            """
        )
        throw ExitError.cdkDependenciesMissing
    }

    private static func runCDKSynthCommand(
        cdkAppURL: URL,
        stackName: String,
        outputDir: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "npx", "cdk", "synth",
            stackName,
            "--output", outputDir.path,
        ]
        process.currentDirectoryURL = cdkAppURL

        // CDK needs credentials and an account/region to synth even though
        // synth itself doesn't touch AWS. Dummy values are sufficient.
        var env = ProcessInfo.processInfo.environment
        env["CDK_DEFAULT_ACCOUNT"] = env["CDK_DEFAULT_ACCOUNT"] ?? "000000000000"
        env["CDK_DEFAULT_REGION"] = env["CDK_DEFAULT_REGION"] ?? "us-east-1"
        env["AWS_ACCESS_KEY_ID"] = env["AWS_ACCESS_KEY_ID"] ?? "test"
        env["AWS_SECRET_ACCESS_KEY"] = env["AWS_SECRET_ACCESS_KEY"] ?? "test"
        env["AWS_REGION"] = env["AWS_REGION"] ?? "us-east-1"
        process.environment = env

        let stderr = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData =
                (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            var message =
                "cdk synth failed in \(cdkAppURL.path) with status \(process.terminationStatus): \(stderrText)"
            if looksLikeMissingCommand(
                status: process.terminationStatus,
                stderr: stderrText
            ) {
                message += "\n" + pathHelp
            }
            writeStderr(message)
            throw ExitError.cdkSynthFailed
        }
    }

    // MARK: - Shared generation pipeline

    private static func generate(
        fromTemplate templateURL: URL,
        outputPath: String,
        typeName: String
    ) throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDir = outputURL.deletingLastPathComponent()

        // Filename used for the staged template copy. Derived from the
        // struct name so two entries cannot collide in the work directory.
        let stagedTemplateFileName = "\(typeName).template.json"
        let stagedTemplateURL = outputDir.appendingPathComponent(stagedTemplateFileName)

        let templateData = try Data(contentsOf: templateURL)

        // Always stage the template copy, even if the template has no Outputs
        // section and we emit an empty Swift file.
        try templateData.write(to: stagedTemplateURL)

        guard let template = try JSONSerialization.jsonObject(with: templateData) as? [String: Any] else {
            writeStderr("Template is not a JSON object: \(templateURL.path)")
            throw ExitError.invalidTemplate
        }

        // The CloudFormation spec requires every template to have a
        // `Resources` section with at least one resource. This is the only
        // strictly-required top-level key — `AWSTemplateFormatVersion` is
        // optional and CDK's default synthesizer omits it. Checking for
        // `Resources` catches genuinely malformed input without rejecting
        // valid CDK-synthesized templates.
        guard let resources = template["Resources"] as? [String: Any],
            !resources.isEmpty
        else {
            writeStderr(
                "Not a valid CloudFormation template (missing or empty Resources section): \(templateURL.path)"
            )
            throw ExitError.invalidTemplate
        }

        let templateBody = String(data: templateData, encoding: .utf8) ?? ""
        let services = inferServices(from: template, templateBody: templateBody)
        let outputKeys = extractOutputKeys(from: template)

        guard !outputKeys.isEmpty else {
            // No Outputs section — nothing to generate
            try "".write(toFile: outputPath, atomically: true, encoding: .utf8)
            return
        }

        let source = generateSource(
            typeName: typeName,
            stagedTemplateFileName: stagedTemplateFileName,
            services: services,
            outputKeys: outputKeys
        )

        try source.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Template Analysis

    private static func inferServices(
        from template: [String: Any],
        templateBody: String
    ) -> [String] {
        var services: Set<String> = ["cloudformation"]

        if let resources = template["Resources"] as? [String: Any] {
            for (_, resource) in resources {
                guard let resourceDict = resource as? [String: Any],
                    let resourceType = resourceDict["Type"] as? String
                else {
                    continue
                }
                for (prefix, service) in serviceMapping where resourceType.hasPrefix(prefix) {
                    services.insert(service)
                }
            }
        }

        // CDK-synthesized templates reference the bootstrap version SSM
        // parameter. When present, the runtime stub needs the SSM service
        // available to PUT the parameter before CreateStack.
        if templateBody.contains(cdkBootstrapMarker) {
            services.insert("ssm")
        }

        return services.sorted()
    }

    private static func extractOutputKeys(from template: [String: Any]) -> [String] {
        guard let outputs = template["Outputs"] as? [String: Any] else {
            return []
        }
        return outputs.keys.sorted()
    }

    // MARK: - Code Generation

    private static func generateSource(
        typeName: String,
        stagedTemplateFileName: String,
        services: [String],
        outputKeys: [String]
    ) -> String {
        let servicesLiteral = services.map { "\"\($0)\"" }.joined(separator: ", ")
        let keysLiteral = outputKeys.map { "\"\($0)\"" }.joined(separator: ", ")

        var lines: [String] = []
        lines.append("// Auto-generated — do not edit.")
        lines.append("import Foundation")
        lines.append("import LocalStack")
        lines.append("")
        lines.append("public struct \(typeName): StackOutputs, Sendable {")
        lines.append("    public static let requiredServices: [String] = [\(servicesLiteral)]")
        lines.append("    public static let expectedOutputKeys: [String] = [\(keysLiteral)]")
        lines.append("")
        lines.append("    public static var templatePath: String {")
        lines.append("        URL(fileURLWithPath: #filePath)")
        lines.append("            .deletingLastPathComponent()")
        lines.append("            .appendingPathComponent(\"\(stagedTemplateFileName)\")")
        lines.append("            .path")
        lines.append("    }")
        lines.append("")
        lines.append("    public let rawOutputs: [String: String]")

        // Typed properties
        for key in outputKeys {
            lines.append("    public let \(camelCase(key)): String")
        }

        // Init
        lines.append("")
        lines.append("    public init(rawOutputs: [String: String]) throws {")
        for key in outputKeys {
            let property = camelCase(key)
            lines.append("        guard let \(property) = rawOutputs[\"\(key)\"] else {")
            lines.append(
                "            throw StackOutputError.missingOutput(key: \"\(key)\", availableKeys: Array(rawOutputs.keys.sorted()))"
            )
            lines.append("        }")
        }
        lines.append("        self.rawOutputs = rawOutputs")
        for key in outputKeys {
            let property = camelCase(key)
            lines.append("        self.\(property) = \(property)")
        }
        lines.append("    }")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Naming Helpers

    /// Converts "BucketName" to "bucketName".
    private static func camelCase(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.lowercased() + string.dropFirst()
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum ExitError: Error {
    case badUsage
    case invalidTemplate
    case cdkDependenciesMissing
    case cdkSynthFailed
}
