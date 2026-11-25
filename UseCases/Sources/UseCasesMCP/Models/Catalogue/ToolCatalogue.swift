import MCP

/// The tools the server serves, as data a test can read without a server, a transport or a
/// process.
struct ToolCatalogue: Sendable {
  let entries: [ToolEntry]

  /// - Parameters:
  ///   - definitions: The tools, in the order they are listed.
  ///   - schemas: Where each tool's output schema comes from.
  init(
    definitions: [ToolDefinition] = ToolDefinition.all,
    schemas: any OutputSchemaLoading,
  ) throws(ToolCatalogueError) {
    var entries: [ToolEntry] = []

    for definition in definitions {
      let outputSchema: Value
      let checker: ToolArgumentChecker

      do {
        outputSchema = try schemas.outputSchema(file: definition.outputSchemaFile)
      } catch {
        throw .outputSchema(
          tool: definition.name,
          reason: error,
        )
      }

      do {
        checker = try ToolArgumentChecker(schema: definition.inputSchema)
      } catch {
        throw .inputSchema(
          tool: definition.name,
          reason: error,
        )
      }

      entries.append(
        ToolEntry(
          definition: definition,
          tool: Tool(
            name: definition.name,
            title: definition.title,
            description: definition.description,
            inputSchema: definition.inputSchema,
            annotations: definition.annotations,
            outputSchema: outputSchema,
          ),
          checker: checker,
        ),
      )
    }

    self.entries = entries
  }

  /// What `tools/list` shows.
  var tools: [Tool] {
    entries.map(\.tool)
  }

  func entry(named name: String) -> ToolEntry? {
    entries.first { entry in
      entry.definition.name == name
    }
  }
}
