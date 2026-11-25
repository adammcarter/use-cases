import Foundation
import MCP
import Testing
import UseCasesCore
@testable import UseCasesMCP

struct BundledOutputSchemasTests {
  private let schemas = BundledOutputSchemas()
  private let writer = JSONValueWriter()

  @Test(arguments: ToolDefinition.all)
  func `every tool's output schema stands alone, as a host with only this schema needs`(
    tool: ToolDefinition,
  ) throws {
    let schema = try schemas.outputSchema(file: tool.outputSchemaFile)
    let text = try #require(writer.text(of: schema))

    #expect(schema.objectValue?["type"] == .string("object"))
    #expect(!text.contains("\"$ref\""))
    #expect(!text.contains("\"$id\""))
    #expect(!text.contains("\"$defs\""))
    #expect(!text.contains("../"))
    #expect(!text.contains(".schema.json"))
  }

  @Test
  func `a schema the build does not hold is missing`() {
    #expect(throws: OutputSchemaError.missing(file: "cli-nothing.schema.json")) {
      try schemas.outputSchema(file: "cli-nothing.schema.json")
    }
  }

  @Test
  func `the refusal document of the command line is among the copies, to hold the tools' own to`() {
    #expect(schemas.files().contains("cli-error.schema.json"))
  }

  @Test
  func `status's schema carries what a reader of the answer needs, copied in`() throws {
    let schema = try schemas.outputSchema(file: "cli-status.schema.json")
    let text = try #require(writer.text(of: schema))

    #expect(text.contains("\"gate\""))
    #expect(text.contains("unverified"))
  }

  @Test
  func `a document the command prints keeps its tool's schema`() throws {
    let schema = try schemas.outputSchema(file: "cli-validate.schema.json")
    let validator = try JSONSchemaValidator(schemaText: #require(writer.text(of: schema)))
    let document = """
    {"output_version": 1, "command": "validate", "valid": true, "use_cases": 2, "ready": 2,
     "draft": 0, "links": 9, "files": ["use-cases/text.yml"], "warnings": []}
    """

    #expect(validator.problems(in: document).isEmpty)
    #expect(!validator.problems(in: #"{"command": "validate"}"#).isEmpty)
  }
}
