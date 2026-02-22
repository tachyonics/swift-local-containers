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
}
