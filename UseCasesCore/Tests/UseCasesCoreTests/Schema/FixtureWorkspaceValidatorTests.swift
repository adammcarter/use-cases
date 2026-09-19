import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// `schema validate-fixtures` is the conformance gate: it walks a workspace,
/// picks the schema each file belongs to by its path, and reports what broke.
/// The fixtures below are the same directories the TypeScript suite validates,
/// so the counts and codes here are that tool's own answers.
struct FixtureWorkspaceValidatorTests {
  private let temporary: TemporaryDirectory

  init() throws {
    temporary = try TemporaryDirectory()
  }

  private func validate(_ fixture: String) throws -> FixtureValidationResult {
    try FixtureWorkspaceValidator.validate(
      workspacePath: SchemaFixtures.fixtureWorkspace(fixture).path,
      registry: SchemaFixtures.registry(),
    )
  }

  @Test
  func `the minimal valid workspace is clean`() throws {
    let result = try validate("minimal-valid")

    #expect(result.isValid)
    #expect(result.isComplete)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `the minimal valid workspace exercises all twenty seven schemas, in order`() throws {
    let result = try validate("minimal-valid")

    #expect(result.validatedSchemaIdentifiers == SchemaRegistry.publicSchemaIdentifiers)
  }

  @Test
  func `the expected state file rides along when it exists`() throws {
    let result = try validate("minimal-valid")

    #expect(result.expectedState != nil)
  }

  @Test
  func `a workspace that does not exist validates only the synthetic contracts`() throws {
    let result = try validate("does-not-exist")

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
    #expect(result.validatedSchemaIdentifiers.count == 20)
    #expect(result.expectedState == nil)
  }

  @Test
  func `a workspace breaking its contracts reports every broken rule in order`() throws {
    let result = try validate("invalid-contracts")

    #expect(result.isValid == false)
    #expect(result.isComplete == false)
    #expect(result.diagnostics.map(\.code) == [
      "use_case.observable_outcomes.required",
      "approval_policy.required",
      "schema.if",
      "enum.invalid_value",
      "enum.invalid_value",
    ])
    #expect(result.diagnostics.allSatisfy { $0.sourcePath == "use-cases/bad.yml" })
    #expect(
      result.diagnostics.allSatisfy { $0.entityIdentifier == "bad.contracts.no_outcomes" },
    )
    #expect(result.validatedSchemaIdentifiers.count == 21)
  }

  @Test
  func `a use case id claimed by two files is reported against the second one`() throws {
    let result = try validate("duplicate-ids")
    let diagnostic = try #require(result.diagnostics.first)

    #expect(result.diagnostics.count == 1)
    #expect(diagnostic.code == "workspace.duplicate_use_case_id")
    #expect(
      diagnostic.message == "Use case 'auth.login.success' appears in both "
        + "use-cases/auth-login-a.yml and use-cases/auth-login-b.yml.",
    )
    #expect(diagnostic.sourcePath == "use-cases/auth-login-b.yml")
    #expect(diagnostic.entityIdentifier == "auth.login.success")
    #expect(diagnostic.relatedIdentifiers == ["use-cases/auth-login-a.yml"])
  }

  @Test
  func `damaged YAML is reported file by file, in path order`() throws {
    let result = try validate("damaged-yaml")

    #expect(result.isValid == false)
    #expect(result.diagnostics.map(\.code) == [
      "yaml.custom_tag_rejected",
      "yaml.duplicate_key",
      "parse_error",
      "yaml.merge_key_rejected",
      "parse_error",
      "mode.required",
      "additional_property",
      "additional_property",
    ])
    #expect(result.diagnostics.map(\.sourcePath) == [
      "custom-tag.yml",
      "duplicate-key.yml",
      "malformed.yml",
      "merge-key.yml",
      "use-cases/malformed-use-case.yml",
      "use-cases/valid-sibling.yml",
      "use-cases/valid-sibling.yml",
      "use-cases/valid-sibling.yml",
    ])
  }

  @Test
  func `a workspace whose references dangle is still schema clean`() throws {
    let result = try validate("broken-reference")

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `a workspace adds the schemas its own files exercise`() throws {
    let result = try validate("evidence-basic")

    #expect(result.isValid)
    #expect(result.validatedSchemaIdentifiers.count == 23)
    for fileName in [
      "use-case-file.schema.json", "workspace-config.schema.json", "demo-capsule.schema.json",
    ] {
      #expect(
        result.validatedSchemaIdentifiers
          .contains(SchemaRegistry.schemaIdentifier(forFileName: fileName)),
      )
    }
  }

  @Test
  func `an evidence ledger is validated line by line`() throws {
    let result = try validate("minimal-valid")

    #expect(
      result.validatedSchemaIdentifiers
        .contains(SchemaRegistry.schemaIdentifier(forFileName: "evidence-event.schema.json")),
    )
  }

  @Test
  func `a broken ledger line is reported with its one-based line number`() throws {
    try temporary.writeFile(
      "evidence/broken.jsonl",
      contents: "{\"schema_version\":1}\n\n{not json}\n",
    )

    let result = try FixtureWorkspaceValidator.validate(
      workspacePath: temporary.url.path,
      registry: SchemaFixtures.registry(),
    )
    let codes = result.diagnostics.map(\.code)

    #expect(result.isValid == false)
    #expect(codes.last == "parse_error")
    #expect(result.diagnostics.last?.sourcePath == "evidence/broken.jsonl:2")
    #expect(result.diagnostics.first?.sourcePath == "evidence/broken.jsonl:1")
  }

  @Test
  func `a file outside the known folders with an unknown suffix is skipped`() throws {
    try temporary.writeFile("README.md", contents: "# not a schema document\n")
    try temporary.writeFile("notes.txt", contents: "free text")

    let result = try FixtureWorkspaceValidator.validate(
      workspacePath: temporary.url.path,
      registry: SchemaFixtures.registry(),
    )

    #expect(result.isValid)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `a stray yaml file is parsed even though no schema claims it`() throws {
    try temporary.writeFile("stray.yaml", contents: "a: [1, 2\n")

    let result = try FixtureWorkspaceValidator.validate(
      workspacePath: temporary.url.path,
      registry: SchemaFixtures.registry(),
    )

    #expect(result.isValid == false)
    #expect(result.diagnostics.map(\.code) == ["parse_error"])
    #expect(result.diagnostics.first?.sourcePath == "stray.yaml")
  }

  @Test
  func `the expected json file is never validated as a document`() throws {
    try temporary.writeFile("expected.json", contents: #"{"expected_state":{"rows":1}}"#)

    let result = try FixtureWorkspaceValidator.validate(
      workspacePath: temporary.url.path,
      registry: SchemaFixtures.registry(),
    )

    #expect(result.isValid)
    #expect(result.expectedState == .object(JSONObject([("rows", .number(1))])))
  }

  @Test(arguments: [
    ("use-cases.yml", "workspace-config.schema.json"),
    ("workflow-modes/continuous.yml", "workflow-mode.schema.json"),
    ("use-cases/valid-sibling.yml", "workflow-mode.schema.json"),
    ("use-cases/rows.yml", "use-case-file.schema.json"),
    ("evidence/events.jsonl", "evidence-event.schema.json"),
    ("demo-capsules/capsule.yml", "demo-capsule.schema.json"),
    ("presentation-plans/plan.json", "presentation-plan.schema.json"),
    ("showcase-runs/run.jsonl", "showcase-event.schema.json"),
  ])
  func `a path picks the schema it is validated against`(
    relativePath: String,
    fileName: String,
  ) {
    #expect(
      FixtureWorkspaceValidator.schemaIdentifier(forFixturePath: relativePath)
        == SchemaRegistry.schemaIdentifier(forFileName: fileName),
    )
  }

  @Test(arguments: ["README.md", "notes.txt", "expected.json", "hosts/codex-cli.yml", "a/b.yml"])
  func `a path no folder claims picks no schema`(relativePath: String) {
    #expect(FixtureWorkspaceValidator.schemaIdentifier(forFixturePath: relativePath) == nil)
  }
}
