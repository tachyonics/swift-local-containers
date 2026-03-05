import Foundation
import Testing

@Suite("ContainerCodeGenTool")
struct ContainerCodeGenToolTests {
    private func toolURL() throws -> URL {
        // Find the products directory via the .xctest bundle
        let productsDir = Bundle.allBundles
            .first { $0.bundlePath.hasSuffix(".xctest") }
            .map { $0.bundleURL.deletingLastPathComponent() }

        var candidates: [URL] = []
        if let productsDir {
            candidates.append(productsDir.appending(path: "ContainerCodeGenTool"))
        }
        // Fallback: check the SwiftPM build directory relative to the package
        candidates.append(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/ContainerCodeGenToolTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // package root
                .appending(path: ".build/debug/ContainerCodeGenTool")
        )

        guard let toolPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw ToolError.toolNotFound(searched: candidates.map(\.path))
        }
        return toolPath
    }

    private func runTool(templateJSON: String) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputFile = tempDir.appending(path: "s3-bucket-template.json")
        let outputFile = tempDir.appending(path: "S3BucketTemplateOutputs.swift")

        try templateJSON.write(to: inputFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = try toolURL()
        process.arguments = [inputFile.path, outputFile.path]

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
        #expect(output.contains("static let templateFileName = \"s3-bucket-template.json\""))
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

    @Test("Produces empty file for non-CF JSON")
    func nonCFTemplateProducesEmptyFile() throws {
        let template = """
            { "name": "not a template" }
            """

        let output = try runTool(templateJSON: template)
        #expect(output.isEmpty)
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
