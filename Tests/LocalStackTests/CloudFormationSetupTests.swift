import Testing

@testable import LocalStack

// MARK: - StackOutputs

private struct FakeOutputs: StackOutputs {
    static let templatePath = "/tmp/fake/my-template.json"
    static let requiredServices = ["cloudformation", "s3"]
    static let expectedOutputKeys = ["BucketName"]
    let rawOutputs: [String: String]
    init(rawOutputs: [String: String]) throws {
        self.rawOutputs = rawOutputs
    }
}

@Suite("StackOutputs")
struct StackOutputsTests {
    @Test("awsEndpoint reads from _awsEndpoint raw output")
    func awsEndpointFromRawOutputs() throws {
        let outputs = try FakeOutputs(
            rawOutputs: ["_awsEndpoint": "http://localhost:4566"]
        )
        #expect(outputs.awsEndpoint == "http://localhost:4566")
    }
}

@Suite("CloudFormationSetup")
struct CloudFormationSetupTests {
    @Test("Default stack name is test-stack")
    func defaultStackName() {
        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")

        #expect(setup.stackName == "test-stack")
        #expect(setup.templatePath == "/tmp/template.json")
        #expect(setup.parameters.isEmpty)
    }

    @Test("Custom parameters are preserved")
    func customParameters() {
        let setup = CloudFormationSetup(
            templatePath: "/tmp/template.json",
            stackName: "my-stack",
            parameters: ["BucketName": "test-bucket"]
        )

        #expect(setup.stackName == "my-stack")
        #expect(setup.parameters["BucketName"] == "test-bucket")
    }

    // MARK: - extractOutputs

    @Test("Extracts multiple outputs from DescribeStacks XML")
    func extractOutputsMultiple() {
        let xml = """
            <DescribeStacksResponse>
              <DescribeStacksResult>
                <Stacks>
                  <member>
                    <Outputs>
                      <member>
                        <OutputKey>BucketName</OutputKey>
                        <OutputValue>my-bucket</OutputValue>
                      </member>
                      <member>
                        <OutputKey>QueueUrl</OutputKey>
                        <OutputValue>http://localhost:4566/queue/test</OutputValue>
                      </member>
                    </Outputs>
                  </member>
                </Stacks>
              </DescribeStacksResult>
            </DescribeStacksResponse>
            """

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.count == 2)
        #expect(outputs["BucketName"] == "my-bucket")
        #expect(outputs["QueueUrl"] == "http://localhost:4566/queue/test")
    }

    @Test("Extracts single output from XML")
    func extractOutputsSingle() {
        let xml = """
            <Outputs>
              <member>
                <OutputKey>TableName</OutputKey>
                <OutputValue>users-table</OutputValue>
              </member>
            </Outputs>
            """

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.count == 1)
        #expect(outputs["TableName"] == "users-table")
    }

    @Test("Returns empty dictionary when Outputs section is missing")
    func extractOutputsMissing() {
        let xml = "<DescribeStacksResponse><DescribeStacksResult></DescribeStacksResult></DescribeStacksResponse>"

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.isEmpty)
    }

    @Test("Returns empty dictionary for empty Outputs section")
    func extractOutputsEmpty() {
        let xml = "<Outputs></Outputs>"

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.isEmpty)
    }

    @Test("Skips member with missing OutputKey")
    func extractOutputsMissingKey() {
        let xml = """
            <Outputs>
              <member>
                <OutputValue>some-value</OutputValue>
              </member>
            </Outputs>
            """

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.isEmpty)
    }

    @Test("Skips member with missing OutputValue")
    func extractOutputsMissingValue() {
        let xml = """
            <Outputs>
              <member>
                <OutputKey>BucketName</OutputKey>
              </member>
            </Outputs>
            """

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.isEmpty)
    }

    @Test("Skips member with empty OutputKey tag")
    func extractOutputsEmptyKey() {
        let xml = """
            <Outputs>
              <member>
                <OutputKey></OutputKey>
                <OutputValue>some-value</OutputValue>
              </member>
            </Outputs>
            """

        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")
        let outputs = setup.extractOutputs(from: xml)
        #expect(outputs.isEmpty)
    }
}
