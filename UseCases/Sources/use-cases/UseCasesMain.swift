import UseCasesCLI

@main
struct UseCasesMain {
  /// The command this executable runs: wiring only, so the command line itself is
  /// tested in UseCasesCLI.
  static let command = UseCasesCommand.self

  /// The MCP surface `use-cases mcp` serves, which the command line does not import (ADR 038).
  static let toolServer = MCPToolServing()

  static func main() async {
    await command.main(toolServer: toolServer)
  }
}
