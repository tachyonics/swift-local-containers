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

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            writeStderr("Usage: ContainerCodeGenTool <template.json> <output.swift>")
            throw ExitError.badUsage
        }

        let templatePath = arguments[1]
        let outputPath = arguments[2]

        let data = try Data(contentsOf: URL(fileURLWithPath: templatePath))
        guard let template = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            writeStderr("Template is not a JSON object: \(templatePath)")
            throw ExitError.invalidTemplate
        }

        guard template["AWSTemplateFormatVersion"] != nil else {
            writeStderr("Not a CloudFormation template: \(templatePath)")
            throw ExitError.invalidTemplate
        }

        let fileName = URL(fileURLWithPath: templatePath).lastPathComponent
        let typeName = typeName(from: fileName)
        let services = inferServices(from: template)
        let outputKeys = extractOutputKeys(from: template)

        guard !outputKeys.isEmpty else {
            // No Outputs section — nothing to generate
            try "".write(toFile: outputPath, atomically: true, encoding: .utf8)
            return
        }

        let source = generateSource(
            typeName: typeName,
            fileName: fileName,
            services: services,
            outputKeys: outputKeys
        )

        try source.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Template Analysis

    private static func inferServices(from template: [String: Any]) -> [String] {
        var services: Set<String> = ["cloudformation"]

        guard let resources = template["Resources"] as? [String: Any] else {
            return services.sorted()
        }

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
        fileName: String,
        services: [String],
        outputKeys: [String]
    ) -> String {
        let servicesLiteral = services.map { "\"\($0)\"" }.joined(separator: ", ")
        let keysLiteral = outputKeys.map { "\"\($0)\"" }.joined(separator: ", ")

        var lines: [String] = []
        lines.append("// Auto-generated from \(fileName) — do not edit.")
        lines.append("import LocalStack")
        lines.append("")
        lines.append("public struct \(typeName): StackOutputs, Sendable {")
        lines.append("    public static let templateFileName = \"\(fileName)\"")
        lines.append("    public static let requiredServices: [String] = [\(servicesLiteral)]")
        lines.append("    public static let expectedOutputKeys: [String] = [\(keysLiteral)]")
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

    /// Converts a file name like "s3-sqs-template.json" to "S3SqsTemplateOutputs".
    private static func typeName(from fileName: String) -> String {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return pascalCase(stem) + "Outputs"
    }

    /// Converts "my-stack-name" to "MyStackName".
    private static func pascalCase(_ string: String) -> String {
        string
            .split(separator: "-")
            .map { capitalizeFirst(String($0)) }
            .joined()
    }

    /// Converts "BucketName" to "bucketName".
    private static func camelCase(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.lowercased() + string.dropFirst()
    }

    private static func capitalizeFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

enum ExitError: Error {
    case badUsage
    case invalidTemplate
}
