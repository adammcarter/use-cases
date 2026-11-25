import Testing
@testable import UseCasesMCP

/// Deleting evidence is a person's decision (chapter 20 §3, ADR 027): no tool runs `prune`.
struct ToolDefinitionPruneTests {
  // @use-case:mcp.tools#swift-tests.person-only
  // @use-case:store.prune#swift-tests.persons-call
  @Test
  func `no tool runs prune`() {
    #expect(!ToolDefinition.all.contains { tool in
      tool.command == "prune" || tool.name.contains("prune")
    })
  }
  // @use-case:end store.prune#swift-tests.persons-call
  // @use-case:end mcp.tools#swift-tests.person-only
}
