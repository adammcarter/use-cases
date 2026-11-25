import Testing
@testable import UseCasesCore

struct StoreJSONWriterTests {
  private let writer = StoreJSONWriter()

  private func text(_ bytes: [UInt8]) -> String {
    bytes.utf8Text
  }

  private static let nested = StoreJSONValue.members([
    "z": .integer(1),
    "a": .array([.string("x"), .null]),
    "m": .members([
      "k": .number(1.5),
    ]),
    "e": .array([]),
    "o": .object([]),
  ])

  @Test
  func `compact has no white space and sorts keys`() {
    #expect(
      text(writer.compact(Self.nested))
        == #"{"a":["x",null],"e":[],"m":{"k":1.5},"o":{},"z":1}"#,
    )
  }

  @Test
  func `pretty indents two spaces, puts a space after the colon and ends with a line feed`() {
    #expect(
      text(writer.pretty(Self.nested)) == """
      {
        "a": [
          "x",
          null
        ],
        "e": [],
        "m": {
          "k": 1.5
        },
        "o": {},
        "z": 1
      }

      """,
    )
  }

  @Test
  func `keys sort by their UTF-8 bytes, so a capital comes before a small letter`() {
    let value = StoreJSONValue.members([
      "b": .integer(1),
      "B": .integer(2),
      "é": .integer(3),
      "z": .integer(4),
    ])

    #expect(text(writer.compact(value)) == #"{"B":2,"b":1,"z":4,"é":3}"#)
  }

  @Test(arguments: [
    ("quote\"", #""quote\"""#),
    ("back\\slash", #""back\\slash""#),
    ("line\nfeed", #""line\u000afeed""#),
    ("tab\there", #""tab\u0009here""#),
    ("slash/kept", #""slash/kept""#),
    ("naïve → ok", #""naïve → ok""#),
    ("\u{7F}", "\"\u{7F}\""),
  ])
  func `a string is escaped the way the canonical encoder does`(
    input: String,
    expected: String,
  ) {
    #expect(text(writer.compact(.string(input))) == expected)
  }

  @Test(arguments: [
    (0.0, "0.0"),
    (1.7, "1.7"),
    (2.0, "2.0"),
    (Double.nan, "null"),
    (Double.infinity, "null"),
  ])
  func `a number JSON cannot hold is written as null, which the schema then refuses`(
    input: Double,
    expected: String,
  ) {
    #expect(text(writer.compact(.number(input))) == expected)
  }

  @Test(arguments: [(true, "true"), (false, "false")])
  func `a boolean is written as the word`(
    flag: Bool,
    expected: String,
  ) {
    #expect(text(writer.compact(.boolean(flag))) == expected)
  }

  @Test
  func `integers are written whole`() {
    #expect(text(writer.compact(.integer(-9_007_199_254_740_991))) == "-9007199254740991")
  }

  @Test
  func `the same value is the same bytes every time`() {
    #expect(writer.pretty(Self.nested) == writer.pretty(Self.nested))
  }
}
