import Foundation

@main
struct ContainerCodeGenTool {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: ContainerCodeGenTool <template.json> <output.swift>\n", stderr)
            exit(1)
        }

        let templatePath = CommandLine.arguments[1]
        let outputPath = CommandLine.arguments[2]

        let data = try Data(contentsOf: URL(fileURLWithPath: templatePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fputs("Error: Template is not a JSON object\n", stderr)
            exit(1)
        }

        // Verify this is a CloudFormation template
        guard json["AWSTemplateFormatVersion"] != nil else {
            // Not a CF template — skip silently (the plugin may pass non-template JSON)
            fputs("Skipping \(templatePath): not a CloudFormation template\n", stderr)
            exit(0)
        }

        let templateFileName = URL(fileURLWithPath: templatePath).lastPathComponent
        let stem = URL(fileURLWithPath: templatePath).deletingPathExtension().lastPathComponent
        let typeName = pascalCase(stem) + "Outputs"

        // Extract resource types to infer services
        let resources = json["Resources"] as? [String: Any] ?? [:]
        var services = Set<String>(["cloudformation"])
        for (_, resource) in resources {
            if let resourceDict = resource as? [String: Any],
                let resourceType = resourceDict["Type"] as? String
            {
                if let service = mapResourceTypeToService(resourceType) {
                    services.insert(service)
                }
            }
        }

        // Extract output keys
        let outputs = json["Outputs"] as? [String: Any] ?? [:]
        let outputKeys = outputs.keys.sorted()

        // Generate Swift code
        let code = generateSwift(
            typeName: typeName,
            templateFileName: templateFileName,
            services: services.sorted(),
            outputKeys: outputKeys
        )

        try code.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Service Mapping

private let resourceTypeToService: [String: String] = [
    "AWS::S3::Bucket": "s3",
    "AWS::S3::BucketPolicy": "s3",
    "AWS::SQS::Queue": "sqs",
    "AWS::SQS::QueuePolicy": "sqs",
    "AWS::SNS::Topic": "sns",
    "AWS::SNS::Subscription": "sns",
    "AWS::DynamoDB::Table": "dynamodb",
    "AWS::DynamoDB::GlobalTable": "dynamodb",
    "AWS::Lambda::Function": "lambda",
    "AWS::Lambda::LayerVersion": "lambda",
    "AWS::Lambda::EventSourceMapping": "lambda",
    "AWS::IAM::Role": "iam",
    "AWS::IAM::Policy": "iam",
    "AWS::IAM::User": "iam",
    "AWS::KMS::Key": "kms",
    "AWS::KMS::Alias": "kms",
    "AWS::Events::Rule": "events",
    "AWS::StepFunctions::StateMachine": "stepfunctions",
    "AWS::ApiGateway::RestApi": "apigateway",
    "AWS::ApiGatewayV2::Api": "apigateway",
    "AWS::Kinesis::Stream": "kinesis",
    "AWS::SecretsManager::Secret": "secretsmanager",
    "AWS::SSM::Parameter": "ssm",
    "AWS::EC2::VPC": "ec2",
    "AWS::EC2::Subnet": "ec2",
    "AWS::EC2::SecurityGroup": "ec2",
    "AWS::Logs::LogGroup": "logs"
]

private func mapResourceTypeToService(_ type: String) -> String? {
    // Direct lookup first
    if let service = resourceTypeToService[type] {
        return service
    }
    // Fallback: extract from AWS::<Service>::* pattern
    let parts = type.split(separator: "::")
    if parts.count >= 2, parts[0] == "AWS" {
        return String(parts[1]).lowercased()
    }
    return nil
}

// MARK: - Code Generation

private func generateSwift(
    typeName: String,
    templateFileName: String,
    services: [String],
    outputKeys: [String]
) -> String {
    let servicesLiteral = services.map { "\"\($0)\"" }.joined(separator: ", ")
    let keysLiteral = outputKeys.map { "\"\($0)\"" }.joined(separator: ", ")

    var lines: [String] = []
    lines.append("// Auto-generated from \(templateFileName) — do not edit.")
    lines.append("import LocalStack")
    lines.append("")
    lines.append("public struct \(typeName): StackOutputs, Sendable {")
    lines.append("    public static let templateFileName = \"\(templateFileName)\"")
    lines.append("    public static let requiredServices: [String] = [\(servicesLiteral)]")
    lines.append("    public static let expectedOutputKeys: [String] = [\(keysLiteral)]")
    lines.append("")
    lines.append("    public let rawOutputs: [String: String]")

    // Generate stored properties
    for key in outputKeys {
        let propName = camelCase(key)
        lines.append("    public let \(propName): String")
    }

    lines.append("")
    lines.append("    public init(rawOutputs: [String: String]) throws {")

    for key in outputKeys {
        let propName = camelCase(key)
        lines.append("        guard let \(propName) = rawOutputs[\"\(key)\"] else {")
        lines.append(
            "            throw StackOutputError.missingOutput(key: \"\(key)\", availableKeys: Array(rawOutputs.keys.sorted()))"
        )
        lines.append("        }")
    }

    lines.append("        self.rawOutputs = rawOutputs")
    for key in outputKeys {
        let propName = camelCase(key)
        lines.append("        self.\(propName) = \(propName)")
    }

    lines.append("    }")
    lines.append("}")
    lines.append("")

    return lines.joined(separator: "\n")
}

// MARK: - Naming Helpers

private func pascalCase(_ string: String) -> String {
    string
        .split(separator: "-")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined()
}

private func camelCase(_ string: String) -> String {
    // Handle PascalCase output keys (e.g. "BucketName" → "bucketName")
    guard !string.isEmpty else { return string }
    let first = string.prefix(1).lowercased()
    return first + string.dropFirst()
}
