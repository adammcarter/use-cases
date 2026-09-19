import Testing
@testable import UseCasesCore

/// Line splitting carries two coordinate systems: UTF-16 code units (the
/// recognizer lexes in them) and UTF-8 bytes (span byte ranges are reported in
/// them). Both are compared against the TypeScript for non-ASCII content.
struct PhysicalLinesTests {
  @Test(arguments: MarkersGoldenCorpus.physicalLineCaseNames)
  func `splits lines with the offsets the TypeScript reports`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "physical_lines")
    let content = try MarkersFixtures.string(entry, "content")
    let expected = try #require(entry["lines"])

    let lines = PhysicalLines.split(content)

    #expect(MarkersFixtures.wire(.array(lines.map(\.jsonValue))) == MarkersFixtures.wire(expected))
  }

  @Test(arguments: MarkersGoldenCorpus.physicalLineCaseNames)
  func `maps a code unit position to its line as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "physical_lines")
    let content = try MarkersFixtures.string(entry, "content")
    let lines = PhysicalLines.split(content)
    let probes = try #require(entry["line_index_of_char"]?.arrayValue)

    for probe in probes {
      let position = try MarkersFixtures.integer(probe, "position")
      let expected = try MarkersFixtures.integer(probe, "line_index")
      let actual = PhysicalLines.lineIndex(containingCodeUnit: position, in: lines)
      #expect((actual ?? -1) == expected, "position \(position)")
    }
  }

  @Test
  func `an emoji is two code units but four bytes`() {
    let lines = PhysicalLines.split("\u{1F600}\r\né")

    #expect(lines.count == 2)
    #expect(lines.first?.codeUnitEnd == 4)
    #expect(lines.first?.byteEnd == 6)
    #expect(lines.last?.codeUnitStart == 4)
    #expect(lines.last?.byteStart == 6)
    #expect(lines.last?.byteEnd == 8)
    #expect(lines.last?.text == "é")
  }
}
