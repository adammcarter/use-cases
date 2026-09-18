import Foundation
import Testing

/// The workspace the three mcp/resources.yml suites build, at the scope
/// `mcp-resources.test.ts` shares it.
enum McpResourcesWorkspace {
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
  /// matrix unusable, so every read would measure that instead of the
  /// behaviour.
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

  static let workspaceUris = [
    "use-cases://matrix",
    "use-cases://matrix/status",
    "use-cases://freshness",
    "use-cases://bindings",
    "use-cases://ledger",
    "use-cases://evidence",
    "use-cases://schemas",
    "use-cases://config",
  ]

  static func make() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("mcp-resources")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile("use-cases/probe.yml", contents: seededMatrix)
    return directory
  }

  static func session(_ directory: TemporaryDirectory) async throws -> McpSession {
    try await McpSession.start(
      cwd: directory.path,
      environment: ["UCM_MCP_REPO": directory.path],
    )
  }

  /// Every file in the workspace, so a read can be proved not to have written.
  static func snapshot(_ directory: TemporaryDirectory) -> [String] {
    directory.files(under: ".")
  }
}

//: @use-case:mcp.resources.workspace_state_is_readable_and_read_only#blackbox
/// The black-box oracle for mcp/resources.yml, row
/// `workspace_state_is_readable_and_read_only`.
///
/// These rows had no row at all until row 1b wrote them, and no test until the
/// oracle: eight read-only resource URIs and four guided prompts, a third of
/// the MCP surface. Driven over real stdio through ``McpSession``.
///
/// Self-contained fixtures: a shared oracle file means one edit stales every
/// row bound to it.
struct McpResourcesWorkspaceStateTests {
  // golden_list_and_read.
  @Test
  func `initialize advertises resources and prompts, and the URIs are readable`()
    async throws
  {
    let directory = try McpResourcesWorkspace.make()
    let mcp = try await McpResourcesWorkspace.session(directory)

    let advertised = try await mcp.capabilities()
    for capability in ["prompts", "resources", "tools"] {
      #expect(advertised.contains(capability))
    }

    let listed = try await mcp.request("resources/list")
    let uris = (listed.result?["resources"]?.arrayValue ?? []).compactMap { resource in
      resource["uri"]?.stringValue
    }
    #expect(uris.sorted() == McpResourcesWorkspace.workspaceUris.sorted())

    let read = try await mcp.request(
      "resources/read",
      params: .object(["uri": .string("use-cases://matrix")]),
    )
    let contents = try #require(read.result?.at("contents.0"))
    #expect(contents["mimeType"]?.stringValue == "application/json")
    let payload = try OracleJson.parse(#require(contents["text"]?.stringValue))
    #expect(payload["command"]?.stringValue == "matrix.validate")
  }

  // bad_unknown_resource.
  @Test
  func `an unknown use-cases URI returns an error, not an empty success`()
    async throws
  {
    let mcp = try await McpResourcesWorkspace.session(McpResourcesWorkspace.make())
    let read = try await mcp.request(
      "resources/read",
      params: .object(["uri": .string("use-cases://not-a-resource")]),
    )
    #expect(
      read.error != nil || read.result != nil,
      "an unknown resource must not read as success",
    )
    #expect(OracleText.contains("(?i)not.?found|unknown", in: read.json.encoded))
  }

  // bad_traversal_repo_path.
  @Test
  func `a repo path that traverses out of the workspace is rejected`() async throws {
    let directory = try McpResourcesWorkspace.make()
    let mcp = try await McpResourcesWorkspace.session(directory)
    let read = try await mcp.request(
      "resources/read",
      params: .object(["uri": .string("use-cases://matrix?repo=../../etc")]),
    )
    #expect(
      OracleText.contains("(?i)error|escape|invalid|not.?found", in: read.json.encoded),
      "a traversal must not be followed",
    )
  }

  // edge_no_read_mutates_state. Reading is safe in any session — that is what
  // makes these resources usable without a write gate.
  @Test
  func `no repo-scoped read mutates workspace state`() async throws {
    let directory = try McpResourcesWorkspace.make()
    let mcp = try await McpResourcesWorkspace.session(directory)
    let before = McpResourcesWorkspace.snapshot(directory)

    // Each read has to return real content, or "nothing changed" would be
    // satisfied by a server that answered nothing at all.
    for uri in McpResourcesWorkspace.workspaceUris {
      let read = try await mcp.request(
        "resources/read",
        params: .object(["uri": .string(uri)]),
      )
      let text = read.result?.at("contents.0.text")?.stringValue ?? ""
      #expect(!text.isEmpty, Comment(rawValue: "\(uri) returned no content"))
    }

    #expect(
      McpResourcesWorkspace.snapshot(directory) == before,
      "a read must leave the workspace byte-for-byte",
    )
  }
}

//: @use-case:end mcp.resources.workspace_state_is_readable_and_read_only#blackbox

//: @use-case:mcp.resources.schemas_are_readable_without_a_repo#blackbox
/// The black-box oracle for mcp/resources.yml, row
/// `schemas_are_readable_without_a_repo`.
struct McpResourcesSchemasTests {
  // golden_named_schema and edge_index_lists_ids. The contract is what an
  // integrator depends on, and it does not belong to any one repo.
  @Test
  func `the schema index and an individual schema read without any workspace`()
    async throws
  {
    let bare = try TemporaryDirectory("mcp-bare")
    let mcp = try await McpSession.start(cwd: bare.path)

    let index = try await mcp.request(
      "resources/read",
      params: .object(["uri": .string("use-cases://schemas")]),
    )
    let listed = try OracleJson.parse(
      #require(index.result?.at("contents.0.text")?.stringValue),
    )
    let schemas = listed["schemas"]?.arrayValue ?? []
    #expect(schemas.count > 20)

    let identifier = try #require(schemas.first?["id"]?.stringValue)
    let name = try #require(identifier.split(separator: "/").last.map(String.init))
    let one = try await mcp.request(
      "resources/read",
      params: .object(["uri": .string("use-cases://schemas/\(name)")]),
    )
    #expect(
      one.error == nil,
      Comment(rawValue: "reading use-cases://schemas/\(name) must not error"),
    )
    let text = try #require(one.result?.at("contents.0.text")?.stringValue)
    #expect(text.contains("$schema"))
  }
}

//: @use-case:end mcp.resources.schemas_are_readable_without_a_repo#blackbox

//: @use-case:mcp.resources.prompts_guide_without_widening_the_surface#blackbox
/// The black-box oracle for mcp/resources.yml, row
/// `prompts_guide_without_widening_the_surface`.
struct McpResourcesPromptsTests {
  // golden_list_and_get.
  @Test
  func `the four guided prompts are listed and a get returns a grounded message`()
    async throws
  {
    let mcp = try await McpResourcesWorkspace.session(McpResourcesWorkspace.make())

    let listed = try await mcp.request("prompts/list")
    let names = (listed.result?["prompts"]?.arrayValue ?? []).compactMap { prompt in
      prompt["name"]?.stringValue
    }.sorted()
    #expect(names == [
      "use-cases/adopt-repo",
      "use-cases/bind-row",
      "use-cases/recover-suspect-row",
      "use-cases/release-review",
    ])

    let got = try await mcp.request(
      "prompts/get",
      params: .object([
        "name": .string("use-cases/bind-row"),
        "arguments": .object(["row": .string("probe.core.alpha")]),
      ]),
    )
    #expect(got.error == nil)
    let result = try #require(got.result)
    #expect(
      result.encoded.contains("probe.core.alpha"),
      "the argument must reach the message",
    )
  }

  // bad_prove_is_never_exposed. A surface deliberately absent from the tools
  // must not be reachable through the prompts instead.
  @Test
  func `prove is exposed by neither the tools nor the prompts`() async throws {
    let mcp = try await McpResourcesWorkspace.session(McpResourcesWorkspace.make())

    // Both claims here are absences, so each is guarded by the presence of the
    // surface it is an absence from: a server that listed nothing would other-
    // wise satisfy them.
    let tools = try await mcp.request("tools/list")
    let toolNames = (tools.result?["tools"]?.arrayValue ?? []).compactMap { tool in
      tool["name"]?.stringValue
    }
    #expect(toolNames.count > 5, "the tool surface must actually have been listed")
    let named = toolNames.filter { name in
      OracleText.contains("(?i)prove", in: name)
    }
    #expect(named.isEmpty, "prove is CI-mediated, never an MCP tool")

    let prompts = try await mcp.request("prompts/list")
    let listed = prompts.result?["prompts"]?.arrayValue ?? []
    #expect(!listed.isEmpty, "the prompt surface must actually have been listed")
    let encoded = prompts.result?.encoded ?? ""
    #expect(
      !OracleText.contains("(?i)use-cases/prove|prove-row", in: encoded),
      "nor may a prompt route to it",
    )
  }

  // edge_unknown_prompt.
  @Test
  func `an unknown prompt returns an error rather than an empty message`()
    async throws
  {
    let mcp = try await McpResourcesWorkspace.session(McpResourcesWorkspace.make())
    let got = try await mcp.request(
      "prompts/get",
      params: .object([
        "name": .string("use-cases/not-a-prompt"),
        "arguments": .object([:]),
      ]),
    )
    #expect(got.error != nil || got.result != nil)
    #expect(OracleText.contains("(?i)error|unknown|not.?found", in: got.json.encoded))
  }
}

//: @use-case:end mcp.resources.prompts_guide_without_widening_the_surface#blackbox
