import Foundation
import Testing
@testable import UseCasesCore

/// The envelope is the CLI's whole public contract (ADR 0007 decision 8): eight
/// keys, in this order, with snake_case spellings and a workspace snapshot whose
/// placeholder values are fixed. The tests compare the encoded TEXT, because key
/// order and a dropped null are exactly what a round trip would hide.
struct CliResultTests {
  private var emptyData: JSONValue {
    .object(JSONObject())
  }

  @Test
  func `the envelope encodes byte for byte like the TypeScript one`() {
    let result = CliResult.make(
      command: "schema.synthetic",
      data: emptyData,
      workspaceRoot: "/w",
      dataRoot: "/w",
    )

    #expect(
      result.jsonText() == #"""
      {"schema_version":1,"protocol_version":1,"command":"schema.synthetic","ok":true,\#
      "complete":true,"data":{},"diagnostics":[],"context":{"workspace_root":"/w",\#
      "data_root":"/w","component_id":"use-cases","workspace_snapshot":\#
      {"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,\#
      "working_tree_digest":\#
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",\#
      "component_id":"use-cases",\#
      "captured_at":"1970-01-01T00:00:00.000Z"}}}
      """#,
    )
  }

  @Test
  func `every caller supplied option lands in the envelope`() {
    let diagnostic = Diagnostic(code: "a.b", severity: .warning, message: "m")
    let result = CliResult.make(
      command: "matrix.list",
      data: JSONValue.object(JSONObject([("use_cases", .array([]))])),
      isComplete: false,
      diagnostics: [diagnostic],
      workspaceRoot: "/w",
      dataRoot: "/d",
      componentIdentifier: "comp",
    )

    #expect(
      result.jsonText() == #"""
      {"schema_version":1,"protocol_version":1,"command":"matrix.list","ok":true,\#
      "complete":false,"data":{"use_cases":[]},"diagnostics":[{"code":"a.b",\#
      "severity":"warning","message":"m","source_path":null,"json_pointer":null,\#
      "entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/w",\#
      "data_root":"/d","component_id":"comp","workspace_snapshot":\#
      {"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,\#
      "working_tree_digest":\#
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",\#
      "component_id":"comp","captured_at":"1970-01-01T00:00:00.000Z"}}}
      """#,
    )
  }

  @Test
  func `an error severity diagnostic forces ok to false whatever the caller asked for`() {
    let result = CliResult.make(
      command: "matrix.list",
      data: emptyData,
      isSuccessful: true,
      diagnostics: [Diagnostic(code: "a.b", message: "m")],
    )

    #expect(result.isSuccessful == false)
  }

  @Test(arguments: [DiagnosticSeverity.info, .warning])
  func `a diagnostic below error leaves ok alone`(severity: DiagnosticSeverity) {
    let result = CliResult.make(
      command: "matrix.list",
      data: emptyData,
      isSuccessful: true,
      diagnostics: [Diagnostic(code: "a.b", severity: severity, message: "m")],
    )

    #expect(result.isSuccessful)
  }

  @Test
  func `a caller can still declare failure without any diagnostic`() {
    let result = CliResult.make(command: "matrix.list", data: emptyData, isSuccessful: false)

    #expect(result.isSuccessful == false)
  }

  @Test
  func `the data root defaults to the workspace root`() {
    let result = CliResult.make(command: "x", data: emptyData, workspaceRoot: "/w")

    #expect(result.context.workspaceRoot == "/w")
    #expect(result.context.dataRoot == "/w")
  }

  @Test
  func `the workspace root defaults to the working directory`() {
    let result = CliResult.make(command: "x", data: emptyData)

    #expect(result.context.workspaceRoot == FileManager.default.currentDirectoryPath)
    #expect(result.context.dataRoot == FileManager.default.currentDirectoryPath)
  }

  @Test
  func `the component id defaults to the product default`() {
    let result = CliResult.make(command: "x", data: emptyData)

    #expect(result.context.componentIdentifier == ProductVersion.defaultComponentIdentifier)
    #expect(
      result.context.workspaceSnapshot.componentIdentifier
        == ProductVersion.defaultComponentIdentifier,
    )
  }

  @Test
  func `the versions are pinned at one`() {
    let result = CliResult.make(command: "x", data: emptyData)

    #expect(result.schemaVersion == 1)
    #expect(result.protocolVersion == 1)
  }

  @Test
  func `the placeholder snapshot is the frozen one`() {
    let snapshot = CliResult.make(command: "x", data: emptyData).context.workspaceSnapshot

    #expect(snapshot.repositoryIdentifier == "unknown")
    #expect(snapshot.versionControlSystem == "unknown")
    #expect(snapshot.headRevision == "unknown")
    #expect(snapshot.isDirty == false)
    #expect(
      snapshot.workingTreeDigest
        == "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    )
    #expect(snapshot.capturedAt == "1970-01-01T00:00:00.000Z")
  }

  @Test
  func `the envelope can be read back as a JSON value for validation`() {
    let result = CliResult.make(command: "schema.synthetic", data: emptyData)
    let value = result.jsonValue()

    #expect(value["command"] == .string("schema.synthetic"))
    #expect(value["ok"] == .bool(true))
    #expect(value["data"] == .object(JSONObject()))
    #expect(value.objectValue?.keys == [
      "schema_version", "protocol_version", "command", "ok", "complete", "data", "diagnostics",
      "context",
    ])
  }

  @Test
  func `the envelope validates against the published cli-result schema`() throws {
    let registry = try SchemaFixtures.registry()
    let result = CliResult.make(command: "schema.synthetic", data: emptyData)

    let validation = registry.validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: "cli-result.schema.json"),
      value: result.jsonValue(),
      sourcePath: nil,
    )

    #expect(validation.isValid)
    #expect(validation.diagnostics.isEmpty)
  }
}
