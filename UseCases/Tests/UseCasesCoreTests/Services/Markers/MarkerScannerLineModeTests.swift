import Testing
@testable import UseCasesCore

struct MarkerScannerLineModeTests {
  private static let open = "// \(MarkerSamples.open)\n"
  private static let close = "// \(MarkerSamples.close)\n"
  private static let innerOpen = "// @use-case:example.other#inner\n"
  private static let innerClose = "// @use-case:end example.other#inner\n"

  private func emptyWarning(
    line: Int,
    identifier: String = MarkerSamples.identifier,
  ) -> String {
    "\(MarkerSamples.file):\(line): empty marker region: \(identifier)"
  }

  @Test
  func `the lines between the sentinel lines are the region`() throws {
    let text = Self.open + "abc\n" + Self.close

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(scan.regions.count == 1)
    #expect(scan.diagnostics.isEmpty)
    #expect(region.target.text == MarkerSamples.identifier)
    #expect(region.target.route?.text == "unit-tests")
    #expect(region.mode == .line)
    #expect(region.byteRange == 48 ..< 52)
    #expect(region.contentRanges == [48 ..< 52])
    #expect(region.lines == 2 ... 2)
    #expect(region.startLine == 2)
    #expect(!region.isEmpty)
    #expect(MarkerSamples.content(of: region, in: text) == "abc\n")
  }

  @Test
  func `nested sentinel lines are inside the span but not the content`() throws {
    let text = Self.open + "abc\n" + Self.innerOpen + "def\n" + Self.innerClose + Self.close

    let scan = try MarkerSamples.scan(text)

    let outer = try #require(scan.regions.first)
    let inner = try #require(scan.regions.last)
    #expect(scan.regions.count == 2)
    #expect(outer.byteRange == 48 ..< 126)
    #expect(outer.contentRanges == [48 ..< 52, 85 ..< 89])
    #expect(MarkerSamples.content(of: outer, in: text) == "abc\ndef\n")
    #expect(outer.lines == 2 ... 4)
    #expect(inner.target.text == "example.other#inner")
    #expect(inner.target.route == nil)
    #expect(inner.byteRange == 85 ..< 89)
    #expect(inner.lines == 4 ... 4)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `adding a nested marker never changes the outer content`() throws {
    let plain = Self.open + "abc\n" + Self.close
    let nested = Self.open + Self.innerOpen + "abc\n" + Self.innerClose + Self.close

    let plainRegion = try #require(MarkerSamples.scan(plain).regions.first)
    let nestedRegion = try #require(MarkerSamples.scan(nested).regions.first)

    #expect(MarkerSamples.content(of: nestedRegion, in: nested) == "abc\n")
    #expect(
      MarkerSamples.content(of: plainRegion, in: plain)
        == MarkerSamples.content(of: nestedRegion, in: nested),
    )
    #expect(nestedRegion.lines == 3 ... 3)
  }

  @Test
  func `decoration on a sentinel line is never content`() throws {
    let text = "/* \(MarkerSamples.open) */\nabc\n# \(MarkerSamples.close) ~~~\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == "abc\n")
    #expect(region.lines == 2 ... 2)
  }

  @Test
  func `code sharing a line with a sentinel is not part of an outer line region`() throws {
    let text = "x = 1; // \(MarkerSamples.open)\nabc\ny = 2; // \(MarkerSamples.close)\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == "abc\n")
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func `a line ends with CR, LF or CRLF alike`(lineEnd: String) throws {
    let text = "// \(MarkerSamples.open)\(lineEnd)abc\(lineEnd)// \(MarkerSamples.close)\(lineEnd)"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == "abc" + lineEnd)
    #expect(region.lines == 2 ... 2)
  }

  @Test
  func `a byte-order mark and CRLF give the same lines, with the bytes counted`() throws {
    let bytes: [UInt8] =
      [0xEF, 0xBB, 0xBF]
        + Array("// \(MarkerSamples.open)\r\nabc\r\n// \(MarkerSamples.close)\r\n".utf8)

    let region = try #require(MarkerSamples.scan(bytes: bytes).regions.first)

    #expect(region.byteRange == 52 ..< 57)
    #expect(region.lines == 2 ... 2)
    #expect(MarkerSamples.content(of: region, in: bytes) == "abc\r\n")
  }

  @Test
  func `the end sentinel line may be the last line with no break after it`() throws {
    let text = Self.open + "abc\n// \(MarkerSamples.close)"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(MarkerSamples.content(of: region, in: text) == "abc\n")
  }

  @Test
  func `several content lines are reported first to last`() throws {
    let text = Self.open + "a\n\nb\n  c\n" + Self.close

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(region.lines == 2 ... 5)
    #expect(MarkerSamples.content(of: region, in: text) == "a\n\nb\n  c\n")
  }

  @Test(
    arguments: [
      ("", 2), ("\n", 2), ("\n\n   \n", 4), ("\t\n\u{0B}\u{0C}\r\n", 3), (" \r\n", 2),
      ("\r\r\n\n", 4),
    ] as [(String, Int)],
  )
  func `no lines or only blank lines between the sentinels is an empty region`(
    inside: String,
    lastLine: Int,
  ) throws {
    let text = Self.open + inside + Self.close

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(region.isEmpty)
    #expect(region.lines == 2 ... lastLine)
    #expect(region.startLine == 2)
    #expect(MarkerSamples.rendered(scan) == [emptyWarning(line: 2)])
    #expect(scan.diagnostics.first?.severity == .warning)
    #expect(scan.diagnostics.first?.code == .emptyMarkerRegion)
  }

  @Test
  func `a region with nothing between its sentinels is reported just after its start`() throws {
    let text = "first\n" + Self.open + Self.close

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(region.lines == 3 ... 3)
    #expect(region.byteRange.isEmpty)
    #expect(region.contentRanges.isEmpty)
  }

  @Test(arguments: ["x\n", " x \n", "\u{A0}\n", "\u{3000}\n", "*/\n", "\u{85}\n", "//\n"])
  func `anything but TAB, LF, VT, FF, CR and SPACE is content`(
    inside: String,
  ) throws {
    let text = Self.open + inside + Self.close

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(!region.isEmpty)
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `only sentinel lines between the sentinels are covered and the region is empty`() throws {
    let text = Self.open + Self.innerOpen + Self.innerClose + Self.close

    let scan = try MarkerSamples.scan(text)

    let outer = try #require(scan.regions.first)
    let inner = try #require(scan.regions.last)
    #expect(outer.lines == 2 ... 3)
    #expect(outer.byteRange == 48 ..< (48 + 33 + 37))
    #expect(outer.contentRanges.isEmpty)
    #expect(outer.isEmpty)
    #expect(inner.lines == 3 ... 3)
    #expect(inner.isEmpty)
    #expect(
      MarkerSamples.rendered(scan) == [
        emptyWarning(line: 2),
        emptyWarning(line: 3, identifier: "example.other#inner"),
      ],
    )
  }

  @Test
  func `blank lines around a nested marker leave both regions empty`() throws {
    let text = Self.open + "\n" + Self.innerOpen + " \n" + Self.innerClose + "  \n" + Self.close

    let scan = try MarkerSamples.scan(text)

    let outer = try #require(scan.regions.first)
    #expect(outer.isEmpty)
    #expect(outer.lines == 2 ... 6)
    #expect(
      MarkerSamples.rendered(scan) == [
        emptyWarning(line: 2),
        emptyWarning(line: 4, identifier: "example.other#inner"),
      ],
    )
  }

  @Test
  func `a marker that opens and closes again gives a region each time, in file order`() throws {
    let text = Self.open + "one\n" + Self.close + "gap\n" + Self.open + "two\n" + Self.close

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.map(\.lines) == [2 ... 2, 6 ... 6])
    #expect(scan.regions.map { MarkerSamples.content(of: $0, in: text) } == ["one\n", "two\n"])
    #expect(scan.regions[0] != scan.regions[1])
  }

  @Test
  func `two regions with identical content are two regions`() throws {
    let text = Self.open + "same\n" + Self.close + Self.open + "same\n" + Self.close

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.count == 2)
    #expect(scan.regions[0].byteRange != scan.regions[1].byteRange)
  }

  @Test
  func `regions come in the order their start sentinels appear, an outer one first`() throws {
    let text = Self.open + Self.innerOpen + "x\n" + Self.innerClose + Self.close
      + Self.innerOpen + "y\n" + Self.innerClose

    let scan = try MarkerSamples.scan(text)

    #expect(
      scan.regions.map(\.target.text) == [
        MarkerSamples.identifier, "example.other#inner", "example.other#inner",
      ],
    )
    #expect(scan.regions.map(\.startLine) == [3, 3, 7])
  }

  @Test
  func `a marker inside a string counts`() throws {
    let text = "let begin = \"@use-case:example.a#b\"\nx\nlet end = \"@use-case:end example.a#b\"\n"

    let region = try #require(MarkerSamples.scan(text).regions.first)

    #expect(region.target.text == "example.a#b")
    #expect(MarkerSamples.content(of: region, in: text) == "x\n")
  }

  @Test
  func `a sentinel line with a malformed id is not content either`() throws {
    let text = Self.open + "abc\n// @use-case:Bad\ndef\n" + Self.close

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(MarkerSamples.content(of: region, in: text) == "abc\ndef\n")
    #expect(region.lines == 2 ... 4)
    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier])
  }
}
