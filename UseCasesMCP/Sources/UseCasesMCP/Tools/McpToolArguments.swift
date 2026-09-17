import UseCasesCore

/// How a tool reads its arguments (packages/mcp/src/toolHandlers.ts): the
/// server declares schemas but never validates against them, so each reader is
/// the only check a value gets.
public enum McpToolArguments {
  /// `typeof value === "string" && value.length > 0 ? value : null` — an empty
  /// string is as absent as a missing key.
  public static func string(
    _ arguments: JSONObject,
    _ name: String,
  ) -> String? {
    guard let text = arguments[name]?.stringValue, !text.isEmpty else {
      return nil
    }
    return text
  }

  /// `typeof value === "number" && Number.isFinite(value)`.
  public static func number(
    _ arguments: JSONObject,
    _ name: String,
  ) -> Double? {
    guard let number = arguments[name]?.numberValue, number.isFinite else {
      return nil
    }
    return number
  }

  /// `args[name] === true`: only the boolean true, never a truthy value.
  public static func boolean(
    _ arguments: JSONObject,
    _ name: String,
  ) -> Bool {
    arguments[name] == .bool(true)
  }

  /// An object, which as in JavaScript excludes null and an array.
  public static func object(
    _ arguments: JSONObject,
    _ name: String,
  ) -> JSONObject? {
    arguments[name]?.objectValue
  }

  /// An array keeps its strings; a bare string is a one-element list, even
  /// when empty; anything else places no constraint.
  public static func strings(
    _ arguments: JSONObject,
    _ name: String,
  ) -> [String] {
    switch arguments[name] {
    case let .array(values):
      values.compactMap(\.stringValue)
    case let .string(text):
      [text]
    default:
      []
    }
  }

  /// `actorType`: `script` and `system` pass; everything else, `user`
  /// included, is recorded as `agent`.
  public static func actorType(_ arguments: JSONObject) -> ShowcaseActorType {
    switch string(arguments, "actor_type") {
    case "script": .script
    case "system": .system
    default: .agent
    }
  }

  /// The same three actors as ``actorType(_:)``, in the evidence ledger's own
  /// spelling. `user` never reaches here: the guard refuses the call first.
  public static func evidenceActorType(_ arguments: JSONObject) -> EvidenceActorType {
    switch actorType(arguments) {
    case .script: .script
    case .system: .system
    default: .agent
    }
  }

  /// Every MCP-recorded event names this host surface unless the caller names
  /// another; the value is passed through unchecked, as the TypeScript casts it.
  public static func hostSurface(_ arguments: JSONObject) -> String {
    string(arguments, "host_surface") ?? defaultHostSurface
  }

  public static let defaultHostSurface = "codex.cli"

  /// SECURITY: an agent may never assert that a human acted. Any of the three
  /// spellings claiming `user` refuses the call before it reaches a handler.
  public static func isTrustedUserClaim(_ arguments: JSONObject) -> Bool {
    string(arguments, "actor_type") == "user"
      || string(arguments, "approver_type") == "user"
      || string(arguments, "trusted_confirmation") == "user"
  }
}
