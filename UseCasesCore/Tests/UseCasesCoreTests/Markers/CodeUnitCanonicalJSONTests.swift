import Testing
@testable import UseCasesCore

/// The marker canonical JSON sorts keys by UTF-16 code unit — NOT the
/// `localeCompare` order the semantic row hash uses. It is a separate algorithm,
/// and every binding-set hash is taken over it, so the order is frozen.
struct CodeUnitCanonicalJSONTests {
  private func object(_ pairs: [(String, JSONValue)]) -> JSONValue {
    .object(JSONObject(pairs))
  }

  @Test(arguments: MarkersGoldenCorpus.canonicalJSONCaseNames)
  func `canonicalizes exactly as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "canonical_json")
    let input = try JSONParser.parse(MarkersFixtures.string(entry, "input"))

    #expect(try CodeUnitCanonicalJSON.encode(input) == MarkersFixtures.string(entry, "canonical"))
    #expect(try CodeUnitCanonicalJSON.sha256(input) == MarkersFixtures.string(entry, "sha256"))
  }

  /// U+1F600 is stored as the surrogate pair D83D DE00, and D83D sorts below
  /// FFFF. Ordering by scalar value — Swift's own `<` — puts it after.
  @Test
  func `a surrogate pair sorts below the last basic plane code unit`() throws {
    let value = object([("\u{FFFF}", .number(1)), ("\u{1F600}", .number(2))])

    #expect(try CodeUnitCanonicalJSON.encode(value) == "{\"\u{1F600}\":2,\"\u{FFFF}\":1}")
  }

  @Test
  func `uppercase sorts before lowercase and dash before underscore`() throws {
    let value = object([
      ("a_b", .number(1)),
      ("a", .number(2)),
      ("a-b", .number(3)),
      ("B", .number(4)),
    ])

    #expect(try CodeUnitCanonicalJSON.encode(value) == #"{"B":4,"a":2,"a-b":3,"a_b":1}"#)
  }

  @Test
  func `differs from the locale-collated semantic form on the same keys`() throws {
    let value = object([("a", .number(1)), ("B", .number(2))])

    #expect(try CodeUnitCanonicalJSON.encode(value) == #"{"B":2,"a":1}"#)
    #expect(CanonicalJSON.encode(value) == #"{"a":1,"B":2}"#)
  }

  @Test(arguments: [Double.infinity, -Double.infinity, Double.nan])
  func `refuses a non-finite number, however deeply nested`(number: Double) {
    let value = JSONValue.array([object([("k", .number(number))])])

    let error = #expect(throws: CodeUnitCanonicalJSONError.self) {
      try CodeUnitCanonicalJSON.encode(value)
    }
    #expect(error?.message == "canonical_json: non-finite numbers are not serializable")
  }

  @Test
  func `hashes text and bytes identically as sha256 over UTF-8`() throws {
    for entry in try MarkersFixtures.section("sha256") {
      let input = try MarkersFixtures.string(entry, "input")

      #expect(try MarkerDigest.sha256(input) == MarkersFixtures.string(entry, "sha256"))
      #expect(try MarkerDigest.sha256(bytes: Array(input.utf8))
        == MarkersFixtures.string(entry, "bytes_sha256"))
    }
  }
}
