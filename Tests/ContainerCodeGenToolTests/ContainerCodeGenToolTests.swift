import Foundation
import Testing

@Suite("ContainerCodeGenTool")
struct ContainerCodeGenToolTests {
    private func toolURL() throws -> URL {
        #if os(Linux)
        let toolPath = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .deletingLastPathComponent()
            .appending(path: "ContainerCodeGenTool")
        #else
        let toolPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/debug/ContainerCodeGenTool")
        #endif

        guard FileManager.default.isExecutableFile(atPath: toolPath.path) else {
            throw ToolError.toolNotFound(searched: [toolPath.path])
        }
        return toolPath
    }

    private func runTool(
        templateJSON: String,
        structName: String = "S3BucketTemplateOutputs"
    ) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputFile = tempDir.appending(path: "s3-bucket-template.json")
        let outputFile = tempDir.appending(path: "\(structName).swift")

        try templateJSON.write(to: inputFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = try toolURL()
        process.arguments = [inputFile.path, outputFile.path, structName]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ToolError.nonZeroExit(status: process.terminationStatus, stderr: errorOutput)
        }

        return try String(contentsOf: outputFile, encoding: .utf8)
    }

    @Test("Generates typed StackOutputs struct from CF template")
    func generatesOutputStruct() throws {
        let template = """
            {
                "AWSTemplateFormatVersion": "2010-09-09",
                "Resources": {
                    "MyBucket": { "Type": "AWS::S3::Bucket" }
                },
                "Outputs": {
                    "BucketName": {
                        "Value": { "Ref": "MyBucket" }
                    },
                    "BucketArn": {
                        "Value": { "Fn::GetAtt": ["MyBucket", "Arn"] }
                    }
                }
            }
            """

        let output = try runTool(templateJSON: template)

        #expect(output.contains("struct S3BucketTemplateOutputs: StackOutputs, Sendable"))
        #expect(output.contains("public static var templatePath: String"))
        #expect(output.contains("S3BucketTemplateOutputs.template.json"))
        #expect(output.contains("\"cloudformation\""))
        #expect(output.contains("\"s3\""))
        #expect(output.contains("public let bucketName: String"))
        #expect(output.contains("public let bucketArn: String"))
        #expect(output.contains("rawOutputs[\"BucketName\"]"))
        #expect(output.contains("rawOutputs[\"BucketArn\"]"))
        #expect(output.contains("StackOutputError.missingOutput"))
    }

    @Test("Infers multiple services from resource types")
    func infersMultipleServices() throws {
        let template = """
            {
                "AWSTemplateFormatVersion": "2010-09-09",
                "Resources": {
                    "MyBucket": { "Type": "AWS::S3::Bucket" },
                    "MyQueue": { "Type": "AWS::SQS::Queue" },
                    "MyTable": { "Type": "AWS::DynamoDB::Table" }
                },
                "Outputs": {
                    "QueueUrl": { "Value": "url" }
                }
            }
            """

        let output = try runTool(templateJSON: template)

        #expect(output.contains("\"cloudformation\""))
        #expect(output.contains("\"dynamodb\""))
        #expect(output.contains("\"s3\""))
        #expect(output.contains("\"sqs\""))
    }

    @Test("Exits with error for non-CF JSON")
    func nonCFTemplateExitsWithError() throws {
        let template = """
            { "name": "not a template" }
            """

        #expect(throws: ToolError.self) {
            try runTool(templateJSON: template)
        }
    }

    @Test("Produces empty file for template with no Outputs")
    func noOutputsProducesEmptyFile() throws {
        let template = """
            {
                "AWSTemplateFormatVersion": "2010-09-09",
                "Resources": {
                    "MyBucket": { "Type": "AWS::S3::Bucket" }
                }
            }
            """

        let output = try runTool(templateJSON: template)
        #expect(output.isEmpty)
    }
}

private enum ToolError: Error, CustomStringConvertible {
    case toolNotFound(searched: [String])
    case nonZeroExit(status: Int32, stderr: String)

    var description: String {
        switch self {
        case .toolNotFound(let searched):
            return "ContainerCodeGenTool not found. Searched: \(searched.joined(separator: ", "))"
        case .nonZeroExit(let status, let stderr):
            return "ContainerCodeGenTool exited with status \(status): \(stderr)"
        }
    }
}
