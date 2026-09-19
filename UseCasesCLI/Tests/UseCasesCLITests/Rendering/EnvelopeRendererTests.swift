import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The generic human view (render.ts): a status header, a YAML-ish dump of
/// `data`, diagnostics with where they point, and the `--json` footer.
struct EnvelopeRendererTests {
  static let footer = "Add --json for the full machine-readable result envelope.\n"

  @Test
  func `writes JSON as the wire form plus a newline`() {
    let envelope = JSONValue.object(JSONObject([("b", .number(1)), ("a", .string("x"))]))

    #expect(EnvelopeRenderer.render(envelope, isJSON: true) == #"{"b":1,"a":"x"}"# + "\n")
  }

  @Test
  func `dumps scalars, empty arrays, scalar arrays and nesting`() {
    let data = JSONValue.object(JSONObject([
      ("text", .string("t")),
      ("count", .number(2.5)),
      ("flag", .bool(false)),
      ("skipped", .null),
      ("empty", .array([])),
      ("scalars", .array([.string("a"), .number(1), .null, .bool(true)])),
      ("nested", .object(JSONObject([("inner", .string("i"))]))),
      ("records", .array([.object(JSONObject([("id", .string("r"))])), .string("s")])),
    ]))
    let envelope = JSONValue.object(JSONObject([
      ("command", .string("probe")),
      ("ok", .bool(true)),
      ("complete", .bool(true)),
      ("data", data),
      ("diagnostics", .array([])),
    ]))

    let expected = """
    \u{2713} probe
      text: t
      count: 2.5
      flag: false
      empty: (none)
      scalars: a, 1, null, true
      nested:
        inner: i
      records:
        -
          id: r
        - s


    """ + Self.footer

    #expect(EnvelopeRenderer.render(envelope, isJSON: false) == expected)
  }

  @Test
  func `marks failure and incompleteness and says where each diagnostic points`() {
    let diagnostics = JSONValue.array([
      .object(JSONObject([
        ("code", .string("e")),
        ("severity", .string("error")),
        ("message", .string("bad")),
        ("source_path", .string("a.yml")),
        ("json_pointer", .string("/x")),
        ("entity_id", .string("row.id")),
      ])),
      .object(JSONObject([
        ("code", .string("w")),
        ("severity", .string("warning")),
        ("message", .string("careful")),
        ("source_path", .string("")),
      ])),
      .object(JSONObject([("code", .string("i")), ("message", .string("note"))])),
    ])
    let envelope = JSONValue.object(JSONObject([
      ("command", .string("probe")),
      ("ok", .bool(false)),
      ("complete", .bool(false)),
      ("data", .object(JSONObject())),
      ("diagnostics", diagnostics),
    ]))

    let expected = """
    \u{2717} probe  (incomplete)

      \u{2717} e: bad
          at a.yml /x (row row.id)
      ! w: careful
      \u{00B7} i: note


    """ + Self.footer

    #expect(EnvelopeRenderer.render(envelope, isJSON: false) == expected)
  }

  @Test(arguments: [
    (JSONValue.string("top"), "  top\n"),
    (.number(3), "  3\n"),
    (.null, ""),
  ])
  func `dumps non-object data`(
    data: JSONValue,
    body: String,
  ) {
    let envelope = JSONValue.object(JSONObject([
      ("command", .string("probe")),
      ("ok", .bool(true)),
      ("data", data),
    ]))

    #expect(
      EnvelopeRenderer.render(envelope, isJSON: false) == "\u{2713} probe\n" + body + "\n" + Self
        .footer,
    )
  }
}
