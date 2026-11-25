import MCP
import Testing
import UseCasesCore
@testable import UseCasesMCP

struct ToolErrorDocumentTests {
  @Test
  func `a usage refusal has the command, the kind usage and the message`() {
    let document = ToolErrorDocument.usage(command: "verify", message: "needs step")

    #expect(document.value == .object([
      "output_version": 1,
      "command": "verify",
      "error": ["kind": "usage", "message": "needs step"],
    ]))
  }

  @Test(arguments: ToolDefinition.all)
  func `a refusal of any tool keeps the command line's own error schema`(
    tool: ToolDefinition,
  ) throws {
    let writer = JSONValueWriter()
    let schema = try BundledOutputSchemas().outputSchema(file: "cli-error.schema.json")
    let validator = try JSONSchemaValidator(schemaText: #require(writer.text(of: schema)))
    let document = ToolErrorDocument.usage(command: tool.command, message: "needs step")

    let text = try #require(writer.text(of: document.value))

    #expect(validator.problems(in: text).isEmpty)
  }
}
