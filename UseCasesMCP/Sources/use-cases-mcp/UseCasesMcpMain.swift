import UseCasesMCP

/// The `use-cases-mcp` executable: an MCP server on stdio and nothing else. It
/// takes no arguments — the two mode switches and the configured repo are read
/// from the environment.
@main
struct UseCasesMcpMain {
  static func main() async throws {
    try await McpStdioServer(environment: .process).run()
  }
}
