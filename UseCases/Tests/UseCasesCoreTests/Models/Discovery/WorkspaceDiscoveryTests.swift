import Testing
@testable import UseCasesCore

struct WorkspaceDiscoveryTests {
  private func discovery(_ diagnostics: [Diagnostic]) throws -> WorkspaceDiscovery {
    try WorkspaceDiscovery(
      scopeTree: ScopeTree(
        root: DiscoveredScope(
          directory: .root,
          parent: nil,
          useCasesDirectory: WorkspacePath(validating: "use-cases"),
          definitionFiles: [],
        ),
        descendants: [],
      ),
      nestedWorkspaces: [],
      unreadableScopes: [],
      diagnostics: diagnostics,
    )
  }

  private func diagnostic(_ severity: DiagnosticSeverity) throws -> Diagnostic {
    try Diagnostic(
      file: WorkspacePath(validating: "a.yml"),
      position: nil,
      code: "x",
      severity: severity,
      message: "m",
    )
  }

  @Test
  func `no diagnostics is valid`() throws {
    #expect(try discovery([]).isValid)
  }

  @Test
  func `warnings alone are valid`() throws {
    #expect(try discovery([diagnostic(.warning)]).isValid)
  }

  @Test
  func `one error makes the workspace invalid`() throws {
    #expect(try !discovery([diagnostic(.warning), diagnostic(.error)]).isValid)
  }
}
