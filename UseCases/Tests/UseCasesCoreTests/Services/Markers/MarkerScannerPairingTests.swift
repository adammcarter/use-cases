import Testing
@testable import UseCasesCore

struct MarkerScannerPairingTests {
  private static let open = "// \(MarkerSamples.open)\n"
  private static let close = "// \(MarkerSamples.close)\n"
  private static let other = "// @use-case:example.success#b\n"
  private static let otherClose = "// @use-case:end example.success#b\n"

  private static let breaks = [
    PairingBreak(
      text: open + "abc\n",
      code: .markerNeverClosed,
      line: 1,
      wording: "never closed",
    ),
    PairingBreak(
      text: "abc\n" + close,
      code: .markerWithoutStart,
      line: 2,
      wording: "has no start",
    ),
    PairingBreak(
      text: open + other + close + otherClose,
      code: .markersCross,
      line: 3,
      wording: "cross",
    ),
    PairingBreak(
      text: open + open + close + close,
      code: .markerNestedInItself,
      line: 2,
      wording: "nested inside itself",
    ),
  ]

  @Test(arguments: Self.breaks)
  func `broken structure is an error with its own wording and no region`(
    found: PairingBreak,
  ) throws {
    let scan = try MarkerSamples.scan(found.text)

    let diagnostic = try #require(scan.diagnostics.first)
    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.count == 1)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.code == found.code)
    #expect(diagnostic.position?.line == found.line)
    #expect(diagnostic.file.text == MarkerSamples.file)
    #expect(diagnostic.message.contains(found.wording))
    #expect(diagnostic.description.hasPrefix("\(MarkerSamples.file):\(found.line): "))
  }

  @Test(
    arguments: [
      "// @use-case:example.nope#x\nz\n",
      "z\n// @use-case:end example.nope#x\n",
      "// @use-case:example.success#nope.x\nz\n",
    ],
  )
  func `a pair that is not well formed is an error whatever it names`(text: String) throws {
    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.map(\.severity) == [.error])
  }

  @Test
  func `crossing pairs are told once, at the end that crosses`() throws {
    let text = Self.open + Self.other + Self.close + Self.otherClose

    let scan = try MarkerSamples.scan(text)

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message.contains(MarkerSamples.identifier))
    #expect(message.contains("example.success#b"))
    #expect(message.contains("line 1"))
    #expect(message.contains("line 2"))
  }

  @Test
  func `a marker nested inside itself names the line it is already open from`() throws {
    let text = "\n" + Self.open + Self.open + Self.close + Self.close

    let scan = try MarkerSamples.scan(text)

    let message = try #require(scan.diagnostics.first?.message)
    #expect(scan.diagnostics.first?.position?.line == 3)
    #expect(message.contains("line 2"))
  }

  @Test
  func `several breaks in one file are all told, in line order`() throws {
    let text =
      "// @use-case:end example.a#b\nx\n// @use-case:example.c#d\ny\n" + Self.open + Self.open

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.compactMap { $0.position?.line } == [1, 3, 5, 6, 6])
    #expect(
      scan.diagnostics.map(\.code) == [
        .markerWithoutStart, .markerNeverClosed, .markerNeverClosed, .markerNestedInItself,
        .markerNeverClosed,
      ],
    )
  }

  @Test
  func `a malformed id takes no part in pairing`() throws {
    let text = "// @use-case:Bad_ID\n// @use-case:end Bad_ID\n// @use-case:example.a\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.count == 3)
    #expect(scan.diagnostics.allSatisfy { $0.code == .malformedMarkerIdentifier })
    #expect(scan.diagnostics.allSatisfy { $0.severity == .warning })
  }

  @Test
  func `a malformed id beside a broken pair is told as a warning next to the error`() throws {
    let text = "// @use-case:Bad\n" + Self.open

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier, .markerNeverClosed])
    #expect(scan.diagnostics.map(\.severity) == [.warning, .error])
  }

  @Test
  func `one broken pair does not hide the others being told`() throws {
    let text = Self.open + Self.other + Self.close + Self.otherClose + Self.open

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.map(\.code).contains(.markersCross))
    #expect(scan.diagnostics.map(\.code).contains(.markerNeverClosed))
  }
}
