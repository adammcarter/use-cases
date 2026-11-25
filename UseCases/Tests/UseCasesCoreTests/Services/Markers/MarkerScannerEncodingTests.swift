import Testing
@testable import UseCasesCore

struct MarkerScannerEncodingTests {
  private static let marked = "// \(MarkerSamples.open)\nabc\n// \(MarkerSamples.close)\n"

  private static let wide: [[UInt8]] = [
    WideEncoding.utf16(marked, bigEndian: false),
    WideEncoding.utf16(marked, bigEndian: true),
    WideEncoding.utf32(marked, bigEndian: false),
    WideEncoding.utf32(marked, bigEndian: true),
  ]

  @Test(
    arguments: [
      Array("".utf8),
      Array("no markers here\n".utf8),
      Array("// @use-cas:a#b\n".utf8),
      Array("// @USE-CASE:a#b\n".utf8),
      [0xE9, 0x0A, 0xC0, 0x80, 0xFF],
      Array(0 ... 255) as [UInt8],
    ] as [[UInt8]],
  )
  func `a file without the sentinel bytes has nothing to say, whatever it holds`(
    bytes: [UInt8],
  ) throws {
    let scan = try MarkerSamples.scan(bytes: bytes)

    #expect(scan == .nothing)
  }

  @Test(
    arguments: [
      [0xE9],
      [0xC0, 0x80],
      [0xED, 0xA0, 0x80],
      [0xE2, 0x82],
      [0xF8, 0x88, 0x80, 0x80, 0x80],
      [0x80, 0x80],
      [0xFF],
    ] as [[UInt8]],
  )
  func `a file with the sentinel that is not strict UTF-8 is warned about and gives no link`(
    fault: [UInt8],
  ) throws {
    let bytes = Array(Self.marked.utf8) + fault

    let scan = try MarkerSamples.scan(bytes: bytes)

    let diagnostic = try #require(scan.diagnostics.first)
    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.count == 1)
    #expect(diagnostic.severity == .warning)
    #expect(diagnostic.code == .unsupportedText)
    #expect(diagnostic.position == nil)
    #expect(diagnostic.file.text == MarkerSamples.file)
    #expect(diagnostic.message.contains("unsupported-text"))
    #expect(diagnostic.message.contains("UTF-8"))
  }

  @Test(arguments: Self.wide)
  func `a UTF-16 or UTF-32 file is warned about once, with no link and no line`(
    bytes: [UInt8],
  ) throws {
    let scan = try MarkerSamples.scan(bytes: bytes)

    let diagnostic = try #require(scan.diagnostics.first)
    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.count == 1)
    #expect(diagnostic.severity == .warning)
    #expect(diagnostic.code == .unsupportedText)
    #expect(diagnostic.position == nil)
    #expect(diagnostic.message.contains("unsupported-text"))
    #expect(diagnostic.message.contains("markers cannot be read"))
  }

  @Test(arguments: [[0xFF, 0xFE], [0xFE, 0xFF], [0x00, 0x00, 0xFE, 0xFF]] as [[UInt8]])
  func `the byte-order mark is judged before the sentinel is looked for`(
    bytes: [UInt8],
  ) throws {
    let scan = try MarkerSamples.scan(bytes: bytes)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.map(\.code) == [.unsupportedText])
  }

  @Test
  func `a UTF-8 byte-order mark is allowed and the markers are read`() throws {
    let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array(Self.marked.utf8)

    let scan = try MarkerSamples.scan(bytes: bytes)

    let region = try #require(scan.regions.first)
    #expect(scan.diagnostics.isEmpty)
    #expect(region.lines == 2 ... 2)
    #expect(MarkerSamples.content(of: region, in: bytes) == "abc\n")
  }

  @Test
  func `a file holding only the sentinel and valid UTF-8 beyond ASCII is read`() throws {
    let text = "// café 日本語 🎉\n// \(MarkerSamples.open)\nλ\n// \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(MarkerSamples.content(of: region, in: text) == "λ\n")
    #expect(region.lines == 3 ... 3)
  }
}
