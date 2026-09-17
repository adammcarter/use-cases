import Testing
import UseCasesCore
@testable import UseCasesMCP

/// The declared surface, and the gates every call passes before a handler runs.
struct McpToolCatalogTests {
  private static let readOnly = McpEnvironment(variables: [:], workingDirectory: "/tmp")
  private static let writeEnabled = McpEnvironment(
    variables: ["UCM_MCP_WRITE": "1"],
    workingDirectory: "/tmp",
  )

  @Test
  func `declares nineteen tools`() {
    #expect(McpToolCatalog.descriptors.count == 19)
  }

  @Test
  func `no tool exposes prove, which is CI-mediated`() {
    let named = McpToolCatalog.descriptors.filter { descriptor in
      descriptor.name.contains("prove")
    }
    #expect(named.isEmpty)
  }

  @Test
  func `approval can be requested but never recorded`() {
    let names = McpToolCatalog.descriptors.map(\.name)
    #expect(names.contains("showcase_request_approval"))
    let recording = names.filter { name in
      name.contains("approve") || name == "use_case_approval_record"
    }
    #expect(recording.isEmpty)
  }

  @Test
  func `every tool declares named parameters with repo required`() throws {
    for descriptor in McpToolCatalog.descriptors {
      let schema = try #require(descriptor.inputSchema.objectValue)
      let properties = try #require(schema["properties"]?.objectValue)
      #expect(properties["repo"] != nil, "\(descriptor.name) must declare repo")
      #expect(!properties.isEmpty, "\(descriptor.name) must declare its parameters")
      #expect(schema["required"]?.arrayValue?.first == .string("repo"))
    }
  }

  @Test
  func `an unknown tool is refused under the mcp unknown command`() async {
    let result = await McpToolCatalog.call(
      name: "not_a_tool",
      arguments: JSONObject(),
      environment: Self.readOnly,
    )
    #expect(result.command == "mcp.unknown")
    #expect(result.diagnostics.map(\.code) == ["mcp.tool_unknown"])
  }

  @Test
  func `a zero budget aborts before the workspace is even resolved`() async {
    let result = await McpToolCatalog.call(
      name: "matrix_validate",
      arguments: JSONObject([("timeout_ms", .number(0))]),
      environment: Self.readOnly,
    )
    #expect(result.diagnostics.map(\.code) == ["mcp.timeout"])
  }

  /// The two write locks report DIFFERENT codes, and which one answers depends
  /// on whether the CALL asked for the write — the call lock is checked first.
  @Test(arguments: [
    (false, false, "mcp.write_mode_required"),
    (false, true, "mcp.write_mode_required"),
    (true, false, "mcp.server_write_mode_required"),
  ])
  func `a mutation names the lock that refused it`(
    allowWrite: Bool,
    sessionEnabled: Bool,
    code: String,
  ) async {
    var arguments = JSONObject([("repo", .string("/tmp"))])
    if allowWrite {
      arguments["allow_write"] = .bool(true)
    }
    let result = await McpToolCatalog.call(
      name: "use_case_upsert",
      arguments: arguments,
      environment: sessionEnabled ? Self.writeEnabled : Self.readOnly,
    )
    #expect(result.command == "matrix.upsert")
    #expect(result.diagnostics.map(\.code) == [code])
  }

  @Test(arguments: ["actor_type", "approver_type", "trusted_confirmation"])
  func `a claim that a user acted is refused whichever way it is spelled`(
    parameter: String,
  ) async {
    let result = await McpToolCatalog.call(
      name: "matrix_validate",
      arguments: JSONObject([
        ("repo", .string("/tmp")),
        (parameter, .string("user")),
      ]),
      environment: Self.readOnly,
    )
    #expect(result.diagnostics.map(\.code) == ["mcp.trusted_confirmation_required"])
  }

  @Test
  func `executing capsule commands needs its own mode`() async {
    let result = await McpToolCatalog.call(
      name: "capsule_run",
      arguments: JSONObject([
        ("repo", .string("/tmp")),
        ("execute_commands", .bool(true)),
        ("allow_write", .bool(true)),
      ]),
      environment: Self.writeEnabled,
    )
    #expect(result.diagnostics.map(\.code) == ["mcp.server_command_execution_mode_required"])
  }

  @Test
  func `a workspace tool without repo is refused rather than guessing one`() async {
    let result = await McpToolCatalog.call(
      name: "matrix_validate",
      arguments: JSONObject(),
      environment: Self.readOnly,
    )
    #expect(result.diagnostics.map(\.code) == ["mcp.repo_required"])
  }
}
