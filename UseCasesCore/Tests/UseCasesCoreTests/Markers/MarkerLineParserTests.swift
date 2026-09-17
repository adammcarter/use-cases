import Testing
@testable import UseCasesCore

/// The marker grammar: `<prefix>: @use-case:<payload>`, identity only.
struct MarkerLineParserTests {
  @Test(arguments: MarkersGoldenCorpus.markerLineCaseNames)
  func `parses a line exactly as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "marker_lines")
    let line = try MarkersFixtures.string(entry, "line")
    let prefix = try MarkersFixtures.string(entry, "prefix")
    let expected = try #require(entry["parse"])

    let parse = MarkerLineParser.parse(line, commentPrefix: prefix)

    #expect(MarkersFixtures.wire(parse.jsonValue) == MarkersFixtures.wire(expected))
  }

  @Test
  func `validates and splits slugs exactly as the TypeScript does`() throws {
    for entry in try MarkersFixtures.section("slugs") {
      let slug = try MarkersFixtures.string(entry, "slug")
      let expectedSplit = try #require(entry["split"])

      #expect(MarkerSlug.isValid(slug) == entry["valid"]?.boolValue, "\(slug)")
      let split = MarkerSlug.split(slug)?.jsonValue ?? .null
      #expect(MarkersFixtures.wire(split) == MarkersFixtures.wire(expectedSplit), "\(slug)")
    }
  }

  @Test
  func `the grammar is checked per code unit, not per character`() {
    let parse = MarkerLineParser.parse("//: @use-case:\u{301}a.b", commentPrefix: "//")

    #expect(parse == .invalid(
      code: .malformedMarker,
      message: "invalid slug: \u{301}a.b",
      column: 1,
      slug: "\u{301}a.b",
    ))
  }

  @Test
  func `the marker error codes are frozen wire strings`() {
    let codes = MarkerErrorCode.allCases.map(\.rawValue)

    #expect(codes == [
      "FORBIDDEN_MARKER_PAYLOAD",
      "MALFORMED_MARKER",
      "MALFORMED_END_MARKER",
      "MISMATCHED_END_MARKER",
      "END_WITHOUT_START",
      "UNSUPPORTED_INFERENCE",
      "NESTED_SPAN",
      "UNBALANCED_IGNORE",
      "DUPLICATE_BINDING_SLUG",
    ])
  }
}
