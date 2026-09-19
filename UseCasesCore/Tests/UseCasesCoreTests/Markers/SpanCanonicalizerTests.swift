import Testing
@testable import UseCasesCore

/// `ucase-span-lines-v2`: the canonical text a span hash is taken over. A single
/// differing byte here changes every recorded span hash.
struct SpanCanonicalizerTests {
  @Test(arguments: MarkersGoldenCorpus.spanCanonicalizerCaseNames)
  func `canonicalizes and hashes exactly as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "span_canon")
    let lines = try MarkersFixtures.strings(entry, "lines")

    #expect(try SpanCanonicalizer.canonicalize(lines) == MarkersFixtures.string(entry, "canonical"))
    #expect(try SpanCanonicalizer.hash(lines) == MarkersFixtures.string(entry, "sha256"))
  }

  @Test
  func `normalizes newlines exactly as the TypeScript does`() throws {
    for entry in try MarkersFixtures.section("normalize_newlines") {
      let input = try MarkersFixtures.string(entry, "input")

      #expect(try SpanCanonicalizer.normalizeNewlines(input) == MarkersFixtures.string(
        entry,
        "output",
      ))
    }
  }

  @Test
  func `a whole-block reindent keeps the hash`() {
    #expect(SpanCanonicalizer.hash(["    a {", "      b", "    }"])
      == SpanCanonicalizer.hash(["a {", "  b", "}"]))
  }

  @Test
  func `a relative indent change moves the hash`() {
    #expect(SpanCanonicalizer.hash(["a", "  b", "    c"])
      != SpanCanonicalizer.hash(["a", "  b", "  c"]))
  }

  @Test
  func `a crlf pair collapses to one newline, not two`() {
    #expect(SpanCanonicalizer.normalizeNewlines("a\r\nb") == "a\nb")
  }
}
