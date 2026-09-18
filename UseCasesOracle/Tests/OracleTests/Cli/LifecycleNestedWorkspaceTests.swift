import Foundation
import Testing

//: @use-case:lifecycle.signals.nested_workspace_is_not_scanned#blackbox
/// The black-box oracle for lifecycle/signals.yml, row
/// `nested_workspace_is_not_scanned`.
struct LifecycleNestedWorkspaceTests {
  /// Put a nested workspace, with its own config and a marked file, at `where`.
  ///
  /// The marker lines here are FIXTURE CONTENT for a workspace the product must
  /// refuse to walk, not a binding in this repository: nothing binds
  /// `nested.row.one`, and the parent's scan is asserted to report it nowhere.
  static func withNestedWorkspace(
    _ workspace: SignalsWorkspace.Workspace,
    at location: String,
  ) throws {
    let marker = "@use-case:"
    try workspace.directory.writeFile(
      "\(location)/use-cases.yml",
      contents: SignalsWorkspace.configuration,
    )
    try workspace.directory.writeFile(
      "\(location)/use-cases/n.yml",
      contents: """
      schema_version: 1
      feature:
        id: nested.row
        name: Nested
        summary: A workspace nested inside another one.
      use_cases:
        - id: nested.row.one
          title: The nested behaviour
          lifecycle: planned
          value_tier: supporting
          journey_role: golden
          usage_frequency: rare

      """,
    )
    try workspace.directory.writeFile(
      "\(location)/src/n.ts",
      contents: """
      //: \(marker)nested.row.one
      export function nested() { return 1; }
      //: \(marker)end nested.row.one

      """,
    )
  }

  // golden_nested_fixture_is_skipped.
  @Test
  func `a directory carrying its own config is not walked by the parent`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    try Self.withNestedWorkspace(workspace, at: "tests/fixtures/nested")
    let scanned = try await SignalsWorkspace.scan(workspace)
    let identifiers = SignalsWorkspace.rows(scanned).compactMap { row in
      row["row_id"]?.stringValue
    }
    #expect(identifiers == ["probe.core.alpha"])
  }

  // bad_no_parent_diagnostics_for_nested_markers. The nested workspace's rows
  // exist only in ITS matrix, so charging them to the parent would fail the
  // parent's integrity gate for something that is not its business.
  @Test
  func `the parent emits no integrity or registry errors for nested markers`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    try Self.withNestedWorkspace(workspace, at: "tests/fixtures/nested")
    let scanned = try await SignalsWorkspace.run(workspace, ["scan", "--repo", "."])

    let integrity = scanned.data.at("status.integrity_errors")?.arrayValue ?? []
    #expect(integrity.isEmpty)
    let registry = scanned.data["registry_errors"]?.arrayValue ?? []
    #expect(registry.isEmpty)
  }

  // edge_any_directory_name. The rule keys on the CONFIG, not on a blessed
  // directory name, so a newly added nested workspace needs no skip entry.
  @Test
  func `it is skipped because of its config, whatever the directory is called`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    try Self.withNestedWorkspace(workspace, at: "vendor/demo-app")
    let scanned = try await SignalsWorkspace.scan(workspace)
    let identifiers = SignalsWorkspace.rows(scanned).compactMap { row in
      row["row_id"]?.stringValue
    }
    #expect(identifiers == ["probe.core.alpha"])
  }

  // edge_root_config_does_not_skip_the_repo. The check applies to CHILD
  // directories: the product root's own config must not skip everything.
  @Test
  func `the product root's own config does not skip the whole repository`()
    async throws
  {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.rows(scanned).count == 1)
    #expect(SignalsWorkspace.rows(scanned).first?["row_id"]?.stringValue == "probe.core.alpha")
  }

  // edge_nested_workspace_still_scans_itself. Its config sits at ITS product
  // root rather than below it, so pointing scan at it works normally.
  @Test
  func `the nested workspace's own scan is unaffected`() async throws {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    try Self.withNestedWorkspace(workspace, at: "vendor/demo-app")
    let scanned = try await SignalsWorkspace.run(
      workspace,
      ["scan", "--repo", "vendor/demo-app"],
    )
    // The claim is that the nested workspace scans ITSELF — it sees its own row
    // and none of the parent's. Its exit code is not the point.
    let identifiers = (scanned.data.at("status.rows")?.arrayValue ?? []).compactMap { row in
      row["row_id"]?.stringValue
    }
    #expect(identifiers.contains("nested.row.one"))
    #expect(!identifiers.contains("probe.core.alpha"))
  }
}

//: @use-case:end lifecycle.signals.nested_workspace_is_not_scanned#blackbox
