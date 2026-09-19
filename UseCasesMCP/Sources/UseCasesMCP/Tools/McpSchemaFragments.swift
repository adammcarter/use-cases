import UseCasesCore

/// The closed value-domains and the property fragments the advertised tool
/// schemas are built from (packages/mcp/src/toolSchemas.ts).
///
/// They are advisory: the server does not validate inbound arguments against
/// the schema — handlers self-validate and still forward every undeclared field
/// — so declaring them only improves self-documentation. Their key order is
/// wire contract all the same, because `tools/list` carries them verbatim.
enum McpSchemaFragments {
  static let hostSurfaces = [
    "claude.cli",
    "claude.desktop",
    "codex.cli",
    "copilot.cli",
    "copilot.github",
    "opencode.cli",
    "unknown",
  ]
  static let actorTypes = ["agent", "script", "system"]
  static let verdicts = ["pass", "partial", "fail", "waived", "blocked"]
  static let failureDecisions = ["continue", "pause_to_fix", "waive_with_reason", "abort"]
  static let evidenceKinds = [
    "manual_observation",
    "agent_observation",
    "command_result",
    "test_result",
    "live_demo",
    "artifact_review",
    "host_conformance",
    "url",
  ]
  static let evidenceResults = ["pass", "fail", "inconclusive", "observed"]
  static let valueTiers = ["critical", "core", "supporting", "long_tail"]
  static let journeyRoles = ["golden", "alternate", "edge", "negative", "failure"]
  static let lifecycles = ["planned", "active", "deprecated", "removed"]
  static let usageFrequencies = ["common", "occasional", "rare"]

  /// `{ type: "string", description }`.
  static func string(_ description: String) -> JSONValue {
    .object(JSONObject([
      ("type", .string("string")),
      ("description", .string(description)),
    ]))
  }

  /// `{ type: "boolean", description }`.
  static func boolean(_ description: String) -> JSONValue {
    .object(JSONObject([
      ("type", .string("boolean")),
      ("description", .string(description)),
    ]))
  }

  /// `{ type: "integer", minimum, description }`.
  static func integer(
    minimum: Double,
    _ description: String,
  ) -> JSONValue {
    .object(JSONObject([
      ("type", .string("integer")),
      ("minimum", .number(minimum)),
      ("description", .string(description)),
    ]))
  }

  /// `{ type: "string", enum, description }`.
  static func enumeration(
    _ values: [String],
    _ description: String,
  ) -> JSONValue {
    .object(JSONObject([
      ("type", .string("string")),
      ("enum", .array(values.map(JSONValue.string))),
      ("description", .string(description)),
    ]))
  }

  /// `{ type: "array", items: { type: "string" }, description }`.
  static func stringArray(_ description: String) -> JSONValue {
    .object(JSONObject([
      ("type", .string("array")),
      ("items", .object(JSONObject([("type", .string("string"))]))),
      ("description", .string(description)),
    ]))
  }

  /// `{ type: "array", items: { type: "string", enum }, description }`.
  static func enumerationArray(
    _ values: [String],
    _ description: String,
  ) -> JSONValue {
    .object(JSONObject([
      ("type", .string("array")),
      ("items", .object(JSONObject([
        ("type", .string("string")),
        ("enum", .array(values.map(JSONValue.string))),
      ]))),
      ("description", .string(description)),
    ]))
  }

  static let repository = string(
    "Repository/workspace root. Required for workspace-scoped tools.",
  )
  static let dataRoot = string(
    "Optional data root, resolved relative to repo (must stay inside repo).",
  )
  static let component = string(
    "Optional component id used to scope resolution within the workspace.",
  )
  static let timeout = integer(
    minimum: 0,
    "Advisory call budget in milliseconds; 0 aborts the call before any execution.",
  )
  static let allowWrite = boolean(
    "Must be true for any ledger mutation. Write tools also require the server to run in "
      + "write mode (UCM_MCP_WRITE=1).",
  )
  static let actorType = enumeration(
    actorTypes,
    "Non-user actor recording the event (defaults to agent). 'user' is rejected over MCP; "
      + "trusted-user approval is CLI-mediated.",
  )
  static let hostSurface = enumeration(
    hostSurfaces,
    "Originating host surface recorded on the event (defaults to codex.cli).",
  )
  static let idempotencyKey = string(
    "Caller-supplied idempotency key; a deterministic key is derived when omitted.",
  )
  static let recordedAt = string("ISO-8601 timestamp override for the appended event.")
  static let run = string("Showcase run id.")
  static let planItem = string("Plan item id within the showcase run.")
  static let expectedHash = string(
    "Expected semantic hash for optimistic-concurrency guarding of the matrix file.",
  )

  /// The full row an upsert writes, documented member by member and still open
  /// so the whole `UseCaseV1` shape passes through.
  static let useCaseObject = JSONValue.object(JSONObject([
    ("type", .string("object")),
    ("description", .string("Full use-case entry (UseCaseV1 shape) to add or replace at its id.")),
    ("properties", .object(JSONObject([
      ("id", string("Canonical use-case id (e.g. 'auth.login').")),
      ("title", string("Human-readable title.")),
      ("lifecycle", enumeration(lifecycles, "Lifecycle state.")),
      ("value_tier", enumeration(valueTiers, "Business value tier.")),
      ("journey_role", enumeration(journeyRoles, "Role of this case within the user journey.")),
      ("usage_frequency", enumeration(usageFrequencies, "How often the case is exercised.")),
      ("tags", stringArray("Free-form tags.")),
    ]))),
    ("required", .array([.string("id")])),
    ("additionalProperties", .bool(true)),
  ]))

  /// A workspace-scoped input schema: always repo/data_root/component/
  /// timeout_ms, repo required, and `additionalProperties` left open for
  /// CLI-parity passthrough.
  static func workspaceSchema(
    _ properties: [(key: String, value: JSONValue)] = [],
    required: [String] = [],
  ) -> JSONValue {
    var declared = JSONObject([
      ("repo", repository),
      ("data_root", dataRoot),
      ("component", component),
      ("timeout_ms", timeout),
    ])
    for property in properties {
      declared[property.key] = property.value
    }
    return .object(JSONObject([
      ("type", .string("object")),
      ("properties", .object(declared)),
      ("required", .array((["repo"] + required).map(JSONValue.string))),
      ("additionalProperties", .bool(true)),
    ]))
  }
}
