import Foundation
import Testing

/// The black-box oracle for mcp/wrapper.yml.
///
/// Two rows about MCP mutating the matrix safely and preserving showcase
/// parity, driven over real stdio through ``McpSession``.
///
/// Self-contained fixtures: a shared oracle file means one edit stales every
/// row bound to it.
struct McpWrapperTests {
  static let workspaceConfiguration = """
  schema_version: 1
  workspace_id: probe
  component_id: probe
  data_root: .
  use_cases_dir: use-cases
  evidence_dir: evidence
  demo_capsules_dir: demo-capsules
  showcase_runs_dir: showcase-runs
  default_workflow_mode: continuous

  """

  /// A complete seed row: `use_cases: []` fails schema.minItems, and mutation
  /// is refused outright against an incomplete matrix.
  static let seededMatrix = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.alpha
      title: Alpha
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so the matrix is complete enough to mutate.
      preconditions: [Nothing.]
      trigger: Nothing.
      scenarios:
        - id: probe.core.alpha.golden_runs
          kind: steps
          steps: [Run it.]
          observable_outcomes: [It passes.]
      observable_outcomes: [It exists.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  static let newRow = OracleJson.object([
    "id": .string("probe.core.beta"),
    "title": .string("Beta"),
    "lifecycle": .string("planned"),
    "value_tier": .string("core"),
    "journey_role": .string("golden"),
    "usage_frequency": .string("common"),
  ])

  static func makeWorkspace() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("mcp-wrapper")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: workspaceConfiguration)
    try directory.writeFile("use-cases/probe.yml", contents: seededMatrix)
    return directory
  }

  static func session(
    _ directory: TemporaryDirectory,
    write: Bool = false,
  ) async throws -> McpSession {
    var environment = ["UCM_MCP_REPO": directory.path]
    if write {
      environment["UCM_MCP_WRITE"] = "1"
    }
    return try await McpSession.start(cwd: directory.path, environment: environment)
  }

  // golden_upsert. The matrix must still be complete AFTER the write, not just
  // before it — otherwise the wrapper could leave a workspace it cannot fix.
  @Test
  func `upsert through MCP returns a matrix upsert envelope and leaves it valid`(
  ) async throws {
    let directory = try Self.makeWorkspace()
    let mcp = try await Self.session(directory, write: true)

    let upserted = try await mcp.callTool("use_case_upsert", arguments: [
      "repo": .string(directory.path),
      "file": .string("use-cases/probe.yml"),
      "use_case": Self.newRow,
      "allow_write": .bool(true),
    ])
    #expect(upserted.envelope.command == "matrix.upsert")
    #expect(upserted.isOk == true, Comment(rawValue: upserted.envelope.json.encoded))
    #expect(upserted.data["status"]?.stringValue == "created")

    let validated = try await mcp.callTool("matrix_validate", arguments: [
      "repo": .string(directory.path),
    ])
    #expect(
      validated.data["valid"]?.boolValue == true,
      "the matrix stays complete after the write",
    )
  }

  // golden_remove. Delete is a lifecycle transition, not a deletion.
  @Test
  func `remove through MCP marks the row removed rather than deleting it`() async throws {
    let directory = try Self.makeWorkspace()
    let mcp = try await Self.session(directory, write: true)
    _ = try await mcp.callTool("use_case_upsert", arguments: [
      "repo": .string(directory.path),
      "file": .string("use-cases/probe.yml"),
      "use_case": Self.newRow,
      "allow_write": .bool(true),
    ])

    let removed = try await mcp.callTool("use_case_remove", arguments: [
      "repo": .string(directory.path),
      "use_case": .string("probe.core.beta"),
      "reason": .string("retired"),
      "allow_write": .bool(true),
    ])
    #expect(removed.envelope.command == "matrix.remove")
    #expect(removed.isOk == true, Comment(rawValue: removed.envelope.json.encoded))

    let text = try directory.readFile("use-cases/probe.yml")
    #expect(text.contains("probe.core.beta"), "the row survives as history")
    #expect(text.contains("lifecycle: removed"))
  }

  // bad_write_without_write_mode. Two independent locks: the session and the
  // call. Missing either is refused.
  @Test
  func `write mode is required at both the session and the call`() async throws {
    let readOnly = try Self.makeWorkspace()
    let readOnlySession = try await Self.session(readOnly)
    let refusedBySession = try await readOnlySession.callTool("use_case_upsert", arguments: [
      "repo": .string(readOnly.path),
      "file": .string("use-cases/probe.yml"),
      "use_case": Self.newRow,
      "allow_write": .bool(true),
    ])
    #expect(refusedBySession.isOk == false)
    #expect(
      refusedBySession.diagnosticCodes.contains("mcp.server_write_mode_required"),
      "the session lock reports its own code",
    )

    let enabled = try Self.makeWorkspace()
    let enabledSession = try await Self.session(enabled, write: true)
    let refusedByCall = try await enabledSession.callTool("use_case_upsert", arguments: [
      "repo": .string(enabled.path),
      "file": .string("use-cases/probe.yml"),
      "use_case": Self.newRow,
    ])
    #expect(refusedByCall.isOk == false, "enabling writes is not a blanket permission")
    #expect(
      refusedByCall.diagnosticCodes.contains("mcp.write_mode_required"),
      "and the call lock reports a DIFFERENT one",
    )
  }

  // bad_path_escape_or_damaged_matrix.
  @Test
  func `a path escape and a damaged matrix each prevent mutation`() async throws {
    let directory = try Self.makeWorkspace()
    let mcp = try await Self.session(directory, write: true)

    let escaped = try await mcp.callTool("use_case_upsert", arguments: [
      "repo": .string(directory.path),
      "file": .string("../escape.yml"),
      "use_case": Self.newRow,
      "allow_write": .bool(true),
    ])
    #expect(escaped.isOk == false)
    let nested = (escaped.data["diagnostics"]?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
    #expect(nested.contains("matrix.mutation_path_escape"))

    let damaged = try Self.makeWorkspace()
    try damaged.writeFile(
      "use-cases/probe.yml",
      contents: "schema_version: 1\nfeature:\n  id: probe.core\n",
    )
    let damagedSession = try await Self.session(damaged, write: true)
    let refused = try await damagedSession.callTool("use_case_upsert", arguments: [
      "repo": .string(damaged.path),
      "file": .string("use-cases/probe.yml"),
      "use_case": Self.newRow,
      "allow_write": .bool(true),
    ])
    #expect(refused.isOk == false, "a damaged matrix cannot be edited further")
  }

  // golden_cli and edge_compiled_stdio_loads_the_packaged_core. Parity has to
  // hold for the artifact that actually ships, which is why this drives the
  // COMPILED server over stdio rather than calling into the module.
  @Test
  func `the compiled server returns CLI envelopes for the showcase family`() async throws {
    let directory = try Self.makeWorkspace()
    let mcp = try await Self.session(directory)

    let planned = try await mcp.callTool("plan_showcase", arguments: [
      "repo": .string(directory.path),
    ])
    let command = try #require(planned.envelope.command)
    #expect(command.contains("plan"), "a CLI command name, not an MCP one")
    #expect(planned.raw.error == nil, "the transport succeeds")

    let status = try await mcp.callTool("matrix_status", arguments: [
      "repo": .string(directory.path),
    ])
    #expect(status.envelope.json["schema_version"] != nil)
    #expect(status.envelope.json["command"] != nil)
  }

  // bad_approval_stays_pending. MCP requests approval; it never appends it.
  @Test
  func `requesting approval through MCP leaves it pending`() async throws {
    let directory = try Self.makeWorkspace()
    let mcp = try await Self.session(directory, write: true)

    let requested = try await mcp.callTool("showcase_request_approval", arguments: [
      "repo": .string(directory.path),
      "run": .string("any-run"),
    ])
    #expect(requested.data["trusted_confirmation_required"]?.boolValue == true)
    #expect(requested.envelope.complete == false, "asking does not finish the act")
  }
}
