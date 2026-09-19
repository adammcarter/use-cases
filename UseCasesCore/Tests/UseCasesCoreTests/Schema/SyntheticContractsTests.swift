import Testing
@testable import UseCasesCore

/// Five gap schemas and the result envelopes have no fixture file, so they are
/// validated against representative samples instead. That is what keeps the
/// "every public schema is validated" conformance claim honest — and it means a
/// sample that stops matching its schema has to fail loudly here.
struct SyntheticContractsTests {
  private func run() throws -> (validated: Set<String>, diagnostics: [Diagnostic]) {
    let registry = try SchemaFixtures.registry()
    var validated = Set<String>()
    var diagnostics: [Diagnostic] = []
    SyntheticContracts.validateCommonContracts(
      registry: registry,
      validatedIdentifiers: &validated,
      diagnostics: &diagnostics,
    )
    return (validated, diagnostics)
  }

  @Test
  func `every synthetic sample matches its schema`() throws {
    let outcome = try run()

    #expect(outcome.diagnostics.map(\.code) == [])
  }

  @Test
  func `the twenty schemas with no fixture are marked validated`() throws {
    let outcome = try run()

    #expect(outcome.validated.count == 20)
  }

  @Test(arguments: [
    "common.schema.json",
    "cli-result.schema.json",
    "matrix-validation-result.schema.json",
    "matrix-list-result.schema.json",
    "matrix-mutation-result.schema.json",
    "evidence-append-result.schema.json",
    "evidence-status-result.schema.json",
    "presentation-plan-result.schema.json",
    "showcase-run-status-result.schema.json",
    "showcase-start-result.schema.json",
    "showcase-event-append-result.schema.json",
    "showcase-finish-result.schema.json",
    "showcase-approval-result.schema.json",
    "marker.schema.json",
    "release-gate-result.schema.json",
    "ledger.schema.json",
    "keyring.schema.json",
    "authority.schema.json",
    "approval-token.schema.json",
    "mcp-tool-results.schema.json",
  ])
  func `the schema is covered synthetically`(fileName: String) throws {
    let outcome = try run()

    #expect(outcome.validated.contains(SchemaRegistry.schemaIdentifier(forFileName: fileName)))
  }

  @Test(arguments: [
    "use-case-file.schema.json",
    "evidence-event.schema.json",
    "demo-capsule.schema.json",
    "presentation-plan.schema.json",
    "showcase-event.schema.json",
    "workspace-config.schema.json",
    "workflow-mode.schema.json",
  ])
  func `a schema with a real fixture is not covered synthetically`(fileName: String) throws {
    let outcome = try run()

    #expect(
      outcome.validated.contains(SchemaRegistry.schemaIdentifier(forFileName: fileName)) == false,
    )
  }

  @Test
  func `the caller's existing diagnostics are kept`() throws {
    let registry = try SchemaFixtures.registry()
    var validated: Set = ["already"]
    var diagnostics = [Diagnostic(code: "earlier", message: "kept")]

    SyntheticContracts.validateCommonContracts(
      registry: registry,
      validatedIdentifiers: &validated,
      diagnostics: &diagnostics,
    )

    #expect(diagnostics.first?.code == "earlier")
    #expect(validated.contains("already"))
  }
}
