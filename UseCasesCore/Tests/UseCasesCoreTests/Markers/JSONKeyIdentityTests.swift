import Testing
@testable import UseCasesCore

/// A JSON object's keys are JavaScript strings: two keys are the same key only
/// when their UTF-16 code units are identical. Swift's `String` equality is
/// canonical equivalence, which would fold `"é"` (U+00E9) and `"e\u{301}"` into
/// ONE member — and every hash taken over that object would then disagree with
/// the ledger TypeScript already wrote.
struct JSONKeyIdentityTests {
  private func codeUnits(_ text: String) -> [UInt16] {
    Array(text.utf16)
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.jsonKeyIdentityCaseNames)
  func `parsing keeps canonically equivalent keys apart, exactly as JavaScript does`(
    caseName: String,
  ) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "json_key_identity")
    let parsed = try MarkersLedgerFixtures.parsed(entry, "text")
    let object = try #require(parsed.objectValue)

    let expectedKeys = try MarkersLedgerFixtures.strings(entry, "keys")

    #expect(object.keys.map(codeUnits) == expectedKeys.map(codeUnits))
    #expect(try MarkersLedgerFixtures.wire(parsed) == MarkersLedgerFixtures.string(entry, "wire"))
    #expect(try CodeUnitCanonicalJSON.encode(parsed)
      == MarkersLedgerFixtures.string(entry, "canonical"))
    #expect(try CodeUnitCanonicalJSON.sha256(parsed)
      == MarkersLedgerFixtures.string(entry, "sha256"))
  }

  @Test
  func `a precomposed key does not read a decomposed member`() {
    let object = JSONObject([("\u{00E9}", .number(1))])

    #expect(object["e\u{0301}"] == nil)
    #expect(object.contains("e\u{0301}") == false)
    #expect(object["\u{00E9}"] == .number(1))
  }

  @Test
  func `assigning an equivalent spelling adds a member rather than replacing one`() {
    var object = JSONObject([("\u{00E9}", .number(1))])
    object["e\u{0301}"] = .number(2)

    #expect(object.count == 2)
    #expect(object["\u{00E9}"] == .number(1))
    #expect(object["e\u{0301}"] == .number(2))
  }

  @Test
  func `removing one spelling leaves the other in place`() {
    var object = JSONObject([("\u{00E9}", .number(1)), ("e\u{0301}", .number(2))])
    object["\u{00E9}"] = nil

    #expect(object.pairs.map(\.key).map(codeUnits) == [codeUnits("e\u{0301}")])
  }

  @Test
  func `objects differing only by an equivalent key spelling are not equal`() {
    let left = JSONObject([("\u{00E9}", .number(1))])
    let right = JSONObject([("e\u{0301}", .number(1))])

    #expect(left != right)
  }
}
