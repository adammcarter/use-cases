import MCP
import Testing
@testable import UseCasesMCP

struct ToolCatalogueTests {
  private func catalogue() throws -> ToolCatalogue {
    try ToolCatalogue(schemas: MockOutputSchemaLoading())
  }

  @Test
  func `the host is shown the thirteen tools with title, description, schemas and hints`() throws {
    let tools = try catalogue().tools

    #expect(tools.map(\.name) == ToolDefinition.all.map(\.name))

    for tool in tools {
      #expect(tool.title?.isEmpty == false)
      #expect(tool.description?.isEmpty == false)
      #expect(tool.inputSchema.objectValue?["type"] == .string("object"))
      #expect(tool.outputSchema?.objectValue?["type"] == .string("object"))
      #expect(!tool.annotations.isEmpty)
    }
  }

  @Test
  func `no title is the tool's name with the server's prefix`() throws {
    for tool in try catalogue().tools {
      #expect(tool.title?.lowercased().hasPrefix("use cases") == false)
    }
  }

  @Test
  func `a tool is found by its name, and a name that is no tool is not found`() throws {
    let catalogue = try catalogue()

    #expect(catalogue.entry(named: "use_cases_status")?.definition.command == "status")
    #expect(catalogue.entry(named: "use_cases_init") == nil)
    #expect(catalogue.entry(named: "status") == nil)
  }

  @Test
  func `each tool's output schema comes from the file its definition names`() throws {
    for entry in try catalogue().entries {
      #expect(
        entry.tool.outputSchema?.objectValue?["title"]
          == .string(entry.definition.outputSchemaFile),
      )
    }
  }

  @Test
  func `a tool whose output schema cannot be loaded makes no catalogue`() {
    #expect(
      throws: ToolCatalogueError.outputSchema(
        tool: "use_cases_validate_files",
        reason: .missing(file: "cli-validate.schema.json"),
      ),
    ) {
      try ToolCatalogue(
        schemas: MockOutputSchemaLoading(refusing: .missing(file: "cli-validate.schema.json")),
      )
    }
  }

  @Test(arguments: ToolDefinition.all)
  func `every tool's own input schema is one the core's checker can run`(
    tool: ToolDefinition,
  ) throws {
    _ = try ToolArgumentChecker(schema: tool.inputSchema)
  }
}
