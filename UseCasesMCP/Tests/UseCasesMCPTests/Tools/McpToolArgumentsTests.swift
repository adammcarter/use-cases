import Testing
import UseCasesCore
@testable import UseCasesMCP

/// The argument readers ARE the validation: the server advertises schemas but
/// never checks an inbound call against them.
struct McpToolArgumentsTests {
  @Test(arguments: [
    (JSONValue.string("value"), "value"),
    (JSONValue.string(""), nil),
    (JSONValue.number(1), nil),
    (JSONValue.bool(true), nil),
    (JSONValue.null, nil),
  ])
  func `a string argument has to be a non-empty string`(
    value: JSONValue,
    expected: String?,
  ) {
    let arguments = JSONObject([("key", value)])
    #expect(McpToolArguments.string(arguments, "key") == expected)
  }

  @Test(arguments: [
    (JSONValue.number(0), 0.0),
    (JSONValue.number(-1), -1.0),
    (JSONValue.string("1"), nil),
    (JSONValue.bool(true), nil),
  ])
  func `a number argument has to be a finite number`(
    value: JSONValue,
    expected: Double?,
  ) {
    let arguments = JSONObject([("key", value)])
    #expect(McpToolArguments.number(arguments, "key") == expected)
  }

  @Test(arguments: [
    (JSONValue.bool(true), true),
    (JSONValue.bool(false), false),
    (JSONValue.string("true"), false),
    (JSONValue.number(1), false),
  ])
  func `a boolean argument is only ever the literal true`(
    value: JSONValue,
    expected: Bool,
  ) {
    let arguments = JSONObject([("key", value)])
    #expect(McpToolArguments.boolean(arguments, "key") == expected)
  }

  @Test
  func `a list argument keeps its strings and drops the rest`() {
    let arguments = JSONObject([
      ("key", .array([.string("a"), .number(1), .string("b"), .null])),
    ])
    #expect(McpToolArguments.strings(arguments, "key") == ["a", "b"])
  }

  @Test
  func `a bare string is a one-element list, even when empty`() {
    #expect(McpToolArguments.strings(JSONObject([("key", .string("a"))]), "key") == ["a"])
    #expect(McpToolArguments.strings(JSONObject([("key", .string(""))]), "key") == [""])
  }

  @Test
  func `an absent list places no constraint`() {
    #expect(McpToolArguments.strings(JSONObject(), "key").isEmpty)
  }

  @Test(arguments: [
    ("script", ShowcaseActorType.script),
    ("system", ShowcaseActorType.system),
    ("agent", ShowcaseActorType.agent),
    ("user", ShowcaseActorType.agent),
    ("nonsense", ShowcaseActorType.agent),
  ])
  func `only script and system displace the agent`(
    value: String,
    expected: ShowcaseActorType,
  ) {
    let arguments = JSONObject([("actor_type", .string(value))])
    #expect(McpToolArguments.actorType(arguments) == expected)
  }

  @Test
  func `the host surface defaults to the MCP one`() {
    #expect(McpToolArguments.hostSurface(JSONObject()) == "codex.cli")
    let named = JSONObject([("host_surface", .string("claude.cli"))])
    #expect(McpToolArguments.hostSurface(named) == "claude.cli")
  }
}
