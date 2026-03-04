import Testing

@testable import LocalStack

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

    @Test("Default timeout and pollInterval")
    func defaultTimeoutAndPollInterval() {
        let setup = CloudFormationSetup(templatePath: "/tmp/template.json")

        #expect(setup.timeout == .seconds(120))
        #expect(setup.pollInterval == .seconds(2))
    }

    @Test("Custom timeout and pollInterval are preserved")
    func customTimeoutAndPollInterval() {
        let setup = CloudFormationSetup(
            templatePath: "/tmp/template.json",
            timeout: .seconds(60),
            pollInterval: .seconds(5)
        )

        #expect(setup.timeout == .seconds(60))
        #expect(setup.pollInterval == .seconds(5))
    }

    // MARK: - buildCreateStackBody

    @Test("Builds basic request body with Action, StackName, and TemplateBody")
    func buildCreateStackBodyBasic() {
        let setup = CloudFormationSetup(
            templatePath: "/tmp/template.json",
            stackName: "my-stack"
        )

        let body = setup.buildCreateStackBody(templateBody: "{\"key\": \"value\"}")

        #expect(body.contains("Action=CreateStack"))
        #expect(body.contains("StackName=my-stack"))
        #expect(body.contains("TemplateBody="))
    }

    @Test("Encodes parameters with member numbering sorted by key")
    func buildCreateStackBodyWithParameters() {
        let setup = CloudFormationSetup(
            templatePath: "/tmp/template.json",
            stackName: "my-stack",
            parameters: ["Zebra": "z-value", "Alpha": "a-value"]
        )

        let body = setup.buildCreateStackBody(templateBody: "{}")

        // Alpha sorts before Zebra
        #expect(body.contains("Parameters.member.1.ParameterKey=Alpha"))
        #expect(body.contains("Parameters.member.1.ParameterValue=a-value"))
        #expect(body.contains("Parameters.member.2.ParameterKey=Zebra"))
        #expect(body.contains("Parameters.member.2.ParameterValue=z-value"))
    }

    @Test("Percent-encodes special characters in template body")
    func buildCreateStackBodyEncodesSpecialCharacters() {
        let setup = CloudFormationSetup(
            templatePath: "/tmp/template.json",
            stackName: "my-stack"
        )

        let body = setup.buildCreateStackBody(templateBody: "key=value&other=123")

        // & and = should be percent-encoded in the template body value
        #expect(body.contains("TemplateBody=key%3Dvalue%26other%3D123"))
    }

    // MARK: - extractStackStatus

    @Test("Extracts CREATE_COMPLETE from XML response")
    func extractStackStatusComplete() {
        let xml = """
            <DescribeStacksResponse>
              <DescribeStacksResult>
                <Stacks>
                  <member>
                    <StackStatus>CREATE_COMPLETE</StackStatus>
                  </member>
                </Stacks>
              </DescribeStacksResult>
            </DescribeStacksResponse>
            """

        #expect(CloudFormationSetup.extractStackStatus(from: xml) == "CREATE_COMPLETE")
    }

    @Test("Extracts CREATE_IN_PROGRESS from XML response")
    func extractStackStatusInProgress() {
        let xml = "<StackStatus>CREATE_IN_PROGRESS</StackStatus>"

        #expect(CloudFormationSetup.extractStackStatus(from: xml) == "CREATE_IN_PROGRESS")
    }

    @Test("Extracts CREATE_FAILED from XML response")
    func extractStackStatusFailed() {
        let xml = "<StackStatus>CREATE_FAILED</StackStatus>"

        #expect(CloudFormationSetup.extractStackStatus(from: xml) == "CREATE_FAILED")
    }

    @Test("Returns UNKNOWN when StackStatus element is missing")
    func extractStackStatusMissing() {
        let xml = "<DescribeStacksResponse><DescribeStacksResult></DescribeStacksResult></DescribeStacksResponse>"

        #expect(CloudFormationSetup.extractStackStatus(from: xml) == "UNKNOWN")
    }

    @Test("Returns UNKNOWN for empty StackStatus element")
    func extractStackStatusEmpty() {
        let xml = "<StackStatus></StackStatus>"

        #expect(CloudFormationSetup.extractStackStatus(from: xml) == "UNKNOWN")
    }
}
