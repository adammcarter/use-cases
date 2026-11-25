import Foundation
import Testing
@testable import UseCasesCore

struct MarkerScannerSameLineTests {
  private static let open = MarkerSamples.open
  private static let close = MarkerSamples.close
  private static let innerOpen = "\(MarkerText.sentinel)example.other#inner"
  private static let innerClose = "\(MarkerText.sentinel)end example.other#inner"

  /// The bytes a range holds, as text.
  private func slice(
    _ bytes: [UInt8],
    _ range: Range<Int>,
  ) -> String {
    String(bytes: bytes[range], encoding: .utf8) ?? ""
  }

  @Test
  func `the bytes between the two tokens are the region`() throws {
    let text = "x = 1 /* \(Self.open) */ call() /* \(Self.close) */\n"
    let bytes = Array(text.utf8)

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(scan.regions.count == 1)
    #expect(region.mode == .sameLine)
    #expect(region.lines == 1 ... 1)
    #expect(region.startLine == 1)
    #expect(slice(bytes, region.byteRange) == " */ call() /* ")
    #expect(region.contentRanges == [region.byteRange])
    #expect(!region.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a nested pair's tokens are left out but the syntax around them stays`() throws {
    let text =
      "x = /* \(Self.open) */ f() + /* \(Self.innerOpen) */ g() /* \(Self.innerClose) */"
        + " /* \(Self.close) */\n"
    let bytes = Array(text.utf8)

    let scan = try MarkerSamples.scan(text)

    let outer = try #require(scan.regions.first)
    let inner = try #require(scan.regions.last)
    let joined = MarkerSamples.content(of: outer, in: bytes)
    #expect(joined == " */ f() + /*  */ g() /*  */ /* ")
    #expect(joined.utf8.count == 31)
    #expect(outer.contentRanges.count == 3)
    #expect(slice(bytes, outer.byteRange).utf8.count > 31)
    #expect(inner.target.text == "example.other#inner")
    #expect(MarkerSamples.content(of: inner, in: bytes) == " */ g() /* ")
    #expect(outer.lines == 1 ... 1)
    #expect(inner.lines == 1 ... 1)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a zero-width region is empty`() throws {
    let text = "\(Self.open)\(Self.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(region.byteRange == 44 ..< 44)
    #expect(region.isEmpty)
    #expect(
      MarkerSamples.rendered(scan) == [
        "\(MarkerSamples.file):1: empty marker region: \(MarkerSamples.identifier)",
      ],
    )
  }

  @Test(arguments: [" ", "\t", " \t ", "\u{0B}\u{0C}", "\r ", "      "])
  func `a same-line region of only whitespace is empty`(inside: String) throws {
    let text = "\(Self.open)\(inside)\(Self.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(region.isEmpty)
    #expect(scan.diagnostics.map(\.code) == [.emptyMarkerRegion])
  }

  @Test(arguments: ["\u{A0}", " x", " . ", "\u{3000}"])
  func `a same-line region holding anything else is not empty`(inside: String) throws {
    let text = "\(Self.open)\(inside)\(Self.close)\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.first?.isEmpty == false)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `comment decoration counts as content`() throws {
    let text = "/* \(Self.open) */ /* \(Self.close) */\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(MarkerSamples.content(of: region, in: text) == " */ /* ")
    #expect(!region.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `a trailing hyphen is not part of the id so it stays content`() throws {
    let text = "<!--\(Self.open)--> x <!--\(Self.close)-->\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(region.target.text == MarkerSamples.identifier)
    #expect(MarkerSamples.content(of: region, in: text) == "--> x <!--")
  }

  @Test
  func `byte offsets count bytes, a byte-order mark and multibyte text included`() throws {
    let bytes: [UInt8] =
      [0xEF, 0xBB, 0xBF] + Array("日本語 /* \(Self.open) */ é /* \(Self.close) */\n".utf8)

    let region = try #require(MarkerSamples.scan(bytes: bytes).regions.first)

    #expect(slice(bytes, region.byteRange) == " */ é /* ")
    #expect(region.byteRange.lowerBound == 3 + 10 + 3 + 44)
    #expect(region.lines == 1 ... 1)
  }

  @Test
  func `a byte-order mark and a same-line pair on the first line`() throws {
    let bytes: [UInt8] =
      [0xEF, 0xBB, 0xBF] + Array("/* \(Self.open) */ f() /* \(Self.close) */\n".utf8)

    let region = try #require(MarkerSamples.scan(bytes: bytes).regions.first)

    #expect(region.byteRange.lowerBound == 3 + 3 + 44)
    #expect(slice(bytes, region.byteRange) == " */ f() /* ")
    #expect(region.lines == 1 ... 1)
  }

  @Test
  func `a sentinel with a malformed id inside is a token to leave out too`() throws {
    let text = "\(Self.open) a \(MarkerText.sentinel)Bad b \(Self.close)\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == " a  b ")
  }

  @Test(
    arguments: [
      "\(MarkerText.sentinel)x.y#zT",
      "\(MarkerText.sentinel)x.y#c_d",
      "\(MarkerText.sentinel)x.y#z-T",
      "\(MarkerText.sentinel)end x.y#zT",
      "\(MarkerText.sentinel)BAD",
      "\(MarkerText.sentinel)x.y#zT_and_a_much_longer_word_of_well_over_forty_characters_in_all",
    ],
  )
  func `a word that follows an id run is part of the sentinel token, not content`(
    sentinel: String,
  ) throws {
    let text = "\(Self.open) a \(sentinel) b \(Self.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(MarkerSamples.content(of: region, in: text) == " a  b ")
    #expect(region.contentRanges.count == 2)
    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier])
  }

  @Test
  func `a trailing hyphen between an id and the word that follows is part of the token`() throws {
    let text = "\(Self.open)\(MarkerText.sentinel)x.y#z-T\(Self.close)\n"
    let bytes = Array(text.utf8)

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(region.byteRange.count == "\(MarkerText.sentinel)x.y#z-T".utf8.count)
    #expect(region.isEmpty)
    #expect(MarkerSamples.content(of: region, in: bytes).isEmpty)
  }

  @Test
  func `a malformed word beside a trimmed trailing hyphen leaves the rest of the region alone`(
  ) throws {
    let text = "\(Self.open) <!--\(MarkerText.sentinel)x.y#zT--> \(Self.close)\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == " <!--" + "--> ")
  }

  @Test
  func `the same binding twice on one line is two regions that share a start line`() throws {
    let text = "/* \(Self.open) */ a /* \(Self.close) */ /* \(Self.open) */ b /* \(Self.close) */\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.count == 2)
    #expect(scan.regions.map(\.startLine) == [1, 1])
    #expect(scan.regions[0].target == scan.regions[1].target)
    #expect(scan.regions[0].byteRange != scan.regions[1].byteRange)
  }

  @Test
  func `each line of a file holds its own same-line regions`() throws {
    let text =
      "a /* \(Self.open) */ one /* \(Self.close) */\n"
        + "b /* \(Self.open) */ two /* \(Self.close) */\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.map(\.startLine) == [1, 2])
    #expect(
      scan.regions.map { MarkerSamples.content(of: $0, in: text) }
        == [" */ one /* ", " */ two /* "],
    )
  }

  @Test
  func `a same-line pair on the line of an empty line region is still told apart`() throws {
    let text =
      "// \(Self.open)\n// \(Self.close) \(Self.innerOpen) x \(Self.innerClose)\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.map(\.mode) == [.line, .sameLine])
    #expect(scan.regions.map(\.startLine) == [2, 2])
  }
}
