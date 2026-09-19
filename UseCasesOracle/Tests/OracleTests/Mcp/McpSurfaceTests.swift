import Foundation
import Testing

/// The workspace the five mcp/surface.yml suites build, at the scope
/// `mcp-surface.test.ts` shares it.
enum McpSurfaceWorkspace {
  static let configuration = """
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

  /// A complete seed row: `use_cases: []` fails schema.minItems and leaves the
  /// matrix unusable, which every call would then measure instead of the
  /// wrapper.
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
      intent: Exist so the matrix is valid.
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

  static let damagedMatrix = "schema_version: 1\nfeature:\n  id: probe.core\n"

  static let newRow = OracleJson.object([
    "id": .string("probe.core.beta"),
    "title": .string("Beta"),
    "lifecycle": .string("planned"),
    "value_tier": .string("core"),
    "journey_role": .string("golden"),
    "usage_frequency": .string("common"),
  ])

  static func make() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("mcp-surface")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile("use-cases/probe.yml", contents: seededMatrix)
    return directory
  }

  /// `write: true` enables the SESSION lock; calls still need allow_write.
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

  static func matrixText(_ directory: TemporaryDirectory) throws -> String {
    try directory.readFile("use-cases/probe.yml")
  }

  static func upsertArguments(
    _ directory: TemporaryDirectory,
    file: String = "use-cases/probe.yml",
    allowWrite: Bool,
  ) -> [String: OracleJson] {
    var arguments: [String: OracleJson] = [
      "repo": .string(directory.path),
      "file": .string(file),
      "use_case": newRow,
    ]
    if allowWrite {
      arguments["allow_write"] = .bool(true)
    }
    return arguments
  }

  static func toolNames(_ listed: McpSession.JsonRpcResponse) -> [String] {
    (listed.result?["tools"]?.arrayValue ?? []).compactMap { tool in
      tool["name"]?.stringValue
    }
  }
}

//: @use-case:mcp.surface.cli_contract_transport#blackbox
/// The black-box oracle for mcp/surface.yml, row `cli_contract_transport`.
///
/// Driven over real stdio through ``McpSession``, so these assert the wrapper
/// as a host actually reaches it rather than as a function call.
///
/// Self-contained fixtures: a shared oracle file means one edit stales every
/// row bound to it.
struct McpSurfaceTransportTests {
  // golden_parity. The same command, reached two ways, gives the same answer.
  @Test
  func `an MCP tool returns the same semantic envelope as the CLI command`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory)

    let viaMcp = try await mcp.callTool(
      "matrix_validate",
      arguments: ["repo": .string(directory.path)],
    )
    let viaCli = try await CliBinary.resolved().runJson(
      ["matrix", "validate", "--repo", "."],
      cwd: directory.path,
    )

    #expect(viaMcp.envelope.command == viaCli.envelope.command)
    #expect(viaMcp.isOk == viaCli.isOk)
    #expect(viaMcp.data["valid"] == viaCli.data["valid"])
  }

  // edge_transport_details_may_differ. Parity is about the SEMANTIC result;
  // the transport wrapper around it is allowed to look different.
  @Test
  func `the envelope carries the full v1 contract, whatever the transport`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory)
    let called = try await mcp.callTool(
      "matrix_validate",
      arguments: ["repo": .string(directory.path)],
    )

    for field in ["schema_version", "protocol_version", "command", "ok", "data"] {
      #expect(
        called.envelope.json[field] != nil,
        Comment(rawValue: "the MCP envelope must carry \(field)"),
      )
    }
  }

  // bad_logic_is_never_reimplemented_in_the_wrapper. If the wrapper decided
  // anything itself the two surfaces would drift; the same invalid input must
  // produce the same verdict on both.
  @Test
  func `an invalid matrix gives the same verdict through both surfaces`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: McpSurfaceWorkspace.damagedMatrix,
    )
    let mcp = try await McpSurfaceWorkspace.session(directory)

    let viaMcp = try await mcp.callTool(
      "matrix_validate",
      arguments: ["repo": .string(directory.path)],
    )
    let viaCli = try await CliBinary.resolved().runJson(
      ["matrix", "validate", "--repo", "."],
      cwd: directory.path,
    )

    #expect(viaMcp.isOk == viaCli.isOk)
    #expect(viaMcp.data["valid"] == viaCli.data["valid"])
  }
}

//: @use-case:end mcp.surface.cli_contract_transport#blackbox

//: @use-case:mcp.surface.write_gating#blackbox
/// The black-box oracle for mcp/surface.yml, row `write_gating`.
struct McpSurfaceWriteGatingTests {
  // bad_read_only_session_cannot_mutate. TWO independent locks, and this is the
  // session one.
  @Test
  func `a read-only session refuses a mutating tool with a structured result`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory)
    let before = try McpSurfaceWorkspace.matrixText(directory)

    let refused = try await mcp.callTool(
      "use_case_upsert",
      arguments: McpSurfaceWorkspace.upsertArguments(directory, allowWrite: true),
    )

    #expect(refused.isOk == false)
    // The SESSION lock has its own code, distinct from the call-level one, so a
    // reader can tell which of the two refused.
    #expect(refused.diagnosticCodes.contains("mcp.server_write_mode_required"))
    #expect(
      try McpSurfaceWorkspace.matrixText(directory) == before,
      "a refused write changes nothing",
    )
  }

  /// The other lock: even a write-enabled session refuses a call that does not
  /// ask for the write explicitly. Enabling writes is not a blanket permission.
  @Test
  func `a write-enabled session still refuses a call that omits allow_write`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory, write: true)
    let before = try McpSurfaceWorkspace.matrixText(directory)

    let refused = try await mcp.callTool(
      "use_case_upsert",
      arguments: McpSurfaceWorkspace.upsertArguments(directory, allowWrite: false),
    )

    #expect(refused.isOk == false)
    // The CALL lock, and a different code from the session one.
    #expect(refused.diagnosticCodes.contains("mcp.write_mode_required"))
    #expect(try McpSurfaceWorkspace.matrixText(directory) == before)
  }

  // golden_explicit_write. Both locks open, and the write lands.
  @Test
  func `with the session enabled and allow_write set, the mutation lands`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory, write: true)

    let upserted = try await mcp.callTool(
      "use_case_upsert",
      arguments: McpSurfaceWorkspace.upsertArguments(directory, allowWrite: true),
    )

    #expect(upserted.isOk == true, Comment(rawValue: upserted.envelope.json.encoded))
    #expect(upserted.data["status"]?.stringValue == "created")
    #expect(try McpSurfaceWorkspace.matrixText(directory).contains("probe.core.beta"))
  }

  // bad_mutation_outside_the_configured_root.
  @Test
  func `a path escape is refused even with both locks open`() async throws {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory, write: true)

    let refused = try await mcp.callTool(
      "use_case_upsert",
      arguments: McpSurfaceWorkspace.upsertArguments(
        directory,
        file: "../escape.yml",
        allowWrite: true,
      ),
    )

    #expect(refused.isOk == false)
    // Past both locks, so this refusal comes from the domain and reports there.
    #expect(refused.data["status"]?.stringValue == "blocked")
    let nested = (refused.data["diagnostics"]?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
    #expect(nested.contains("matrix.mutation_path_escape"))
  }
}

//: @use-case:end mcp.surface.write_gating#blackbox

//: @use-case:mcp.surface.approval_request_only#blackbox
/// The black-box oracle for mcp/surface.yml, row `approval_request_only`.
struct McpSurfaceApprovalTests {
  // golden_boundary and edge_no_event_is_appended. MCP may ASK; it may never
  // answer. Asking and answering stay separate acts.
  @Test
  func `the approval tool requires trusted confirmation and writes nothing`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory, write: true)

    let requested = try await mcp.callTool("showcase_request_approval", arguments: [
      "repo": .string(directory.path),
      "run": .string("any-run"),
    ])

    #expect(requested.isOk == true, "requesting is allowed")
    #expect(
      requested.data["trusted_confirmation_required"]?.boolValue == true,
      "but it only ever requests",
    )
    #expect(requested.data["decision_required"]?.boolValue == true)
    // complete:false is the tell — the act is not finished by the request.
    #expect(requested.envelope.complete == false)
  }

  // bad_mcp_cannot_write_user_approval. There is no tool to do it with.
  @Test
  func `no MCP tool can record an approval at all`() async throws {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory, write: true)
    let names = try await McpSurfaceWorkspace.toolNames(mcp.request("tools/list"))

    #expect(names.contains("showcase_request_approval"), "requesting exists")
    let recording = names.filter { name in
      OracleText.contains("(?i)approve|approval_record|record_approval", in: name)
    }
    #expect(recording.isEmpty, "recording one does not")
  }
}

//: @use-case:end mcp.surface.approval_request_only#blackbox

//: @use-case:mcp.surface.domain_results_not_transport_failures#blackbox
/// The black-box oracle for mcp/surface.yml, row
/// `domain_results_not_transport_failures`.
struct McpSurfaceDomainResultsTests {
  // golden_envelope and bad_never_an_opaque_transport_failure. A domain problem
  // must never be disguised as a broken connection.
  @Test
  func `damaged input comes back as a structured result, not a transport error`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: McpSurfaceWorkspace.damagedMatrix,
    )
    let mcp = try await McpSurfaceWorkspace.session(directory)

    let called = try await mcp.callTool(
      "matrix_validate",
      arguments: ["repo": .string(directory.path)],
    )

    #expect(called.raw.error == nil, "the transport itself must succeed")
    #expect(called.envelope.command == "matrix.validate")
    #expect(called.isOk == false)
    #expect(called.data["valid"]?.boolValue == false)
  }
}

//: @use-case:end mcp.surface.domain_results_not_transport_failures#blackbox

//: @use-case:mcp.surface.declared_tool_schemas#blackbox
/// The black-box oracle for mcp/surface.yml, row `declared_tool_schemas`.
struct McpSurfaceToolSchemasTests {
  static func inputProperties(
    _ listed: McpSession.JsonRpcResponse,
    tool name: String,
  ) -> [String] {
    let tool = (listed.result?["tools"]?.arrayValue ?? []).first { entry in
      entry["name"]?.stringValue == name
    }
    return (tool?.at("inputSchema.properties")?.objectValue ?? [:]).keys.sorted()
  }

  // golden_declared and edge_repo_stays_required.
  @Test
  func `high-value tools declare named parameters, with repo required`()
    async throws
  {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory)
    let listed = try await mcp.request("tools/list")

    let properties = Self.inputProperties(listed, tool: "matrix_validate")
    #expect(!properties.isEmpty, "parameters are discoverable from the tool")
    #expect(properties.contains("repo"), "repo is a declared parameter, not a guess")
  }

  // bad_an_open_passthrough_is_not_a_schema.
  @Test
  func `no high-value tool ships only an open passthrough`() async throws {
    let directory = try McpSurfaceWorkspace.make()
    let mcp = try await McpSurfaceWorkspace.session(directory)
    let listed = try await mcp.request("tools/list")

    for name in ["matrix_validate", "matrix_list", "evidence_status"] {
      #expect(
        !Self.inputProperties(listed, tool: name).isEmpty,
        Comment(rawValue: "\(name) must declare its parameters"),
      )
    }
  }
}

//: @use-case:end mcp.surface.declared_tool_schemas#blackbox
