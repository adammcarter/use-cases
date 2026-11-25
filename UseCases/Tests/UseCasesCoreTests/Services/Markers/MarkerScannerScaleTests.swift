import Testing
@testable import UseCasesCore

/// The inputs are sized so a scan that is linear in the file ends at once, while one that is
/// quadratic in the number of regions, or in how deep they nest, runs for minutes or runs out of
/// memory. Nothing is timed and no test carries a time limit: a scan that never ends shows as a
/// run that does not end, and what each test checks is the answer.
struct MarkerScannerScaleTests {
  private static let depth = 30000

  @Test
  func `an empty file has nothing to say`() throws {
    #expect(try MarkerSamples.scan("") == .nothing)
  }

  @Test
  func `a file of 100000 lines in 30000 flat regions is scanned to its end`() throws {
    var text = ""
    text.reserveCapacity(4_000_000)

    for index in 0 ..< 30000 {
      text += "// \(MarkerText.sentinel)example.big#binding-\(index % 50)\n"
      text += "let value = \(index) // ordinary code\n"
      text += "// \(MarkerText.sentinel)end example.big#binding-\(index % 50)\n"
    }

    text += String(repeating: "let filler = 1\n", count: 10000)

    let scan = try MarkerSamples.scan(text)

    #expect(LineIndex(Array(text.utf8)).lineCount == 100_000)
    #expect(scan.regions.count == 30000)
    #expect(scan.diagnostics.isEmpty)
    #expect(scan.regions.last?.lines == 89999 ... 89999)
  }

  @Test
  func `line regions nested 30000 deep are scanned to their end, with every region found`() throws {
    var text = ""

    for index in 0 ..< Self.depth {
      text += "// \(MarkerText.sentinel)example.nest#binding-\(index)\nx\n"
    }

    for index in (0 ..< Self.depth).reversed() {
      text += "// \(MarkerText.sentinel)end example.nest#binding-\(index)\nx\n"
    }

    let scan = try MarkerSamples.scan(text)

    let outermost = try #require(scan.regions.first)
    let innermost = try #require(scan.regions.dropFirst(Self.depth - 1).first)
    #expect(scan.regions.count == Self.depth)
    #expect(scan.diagnostics.isEmpty)
    #expect(outermost.lines == 2 ... (4 * Self.depth - 2))
    #expect(outermost.contentRanges.count == 2 * Self.depth - 1)
    #expect(innermost.lines == (2 * Self.depth) ... (2 * Self.depth))
    #expect(innermost.contentRanges.count == 1)
    #expect(scan.regions.allSatisfy { !$0.isEmpty })
  }

  @Test
  func `same-line regions nested 30000 deep are scanned to their end, with every region found`(
  ) throws {
    var text = ""

    for index in 0 ..< Self.depth {
      text += "/*\(MarkerText.sentinel)example.nest#binding-\(index)*/ x "
    }

    for index in (0 ..< Self.depth).reversed() {
      text += "/*\(MarkerText.sentinel)end example.nest#binding-\(index)*/ x "
    }

    let scan = try MarkerSamples.scan(text)

    let outermost = try #require(scan.regions.first)
    let innermost = try #require(scan.regions.dropFirst(Self.depth - 1).first)
    #expect(scan.regions.count == Self.depth)
    #expect(scan.diagnostics.isEmpty)
    #expect(outermost.contentRanges.count == 2 * Self.depth - 1)
    #expect(innermost.contentRanges.count == 1)
    #expect(MarkerSamples.content(of: innermost, in: text) == "*/ x /*")
    #expect(scan.regions.allSatisfy { !$0.isEmpty && $0.lines == 1 ... 1 })
  }

  /// Blank regions nested `depth` deep. Every one of them is empty, so each carries its own
  /// warning, and ordering those warnings is most of the work.
  private func scanBlankNest(depth: Int) throws -> MarkerScan {
    var text = ""

    for index in 0 ..< depth {
      text += "\(MarkerText.sentinel)example.nest#binding-\(index) "
    }

    for index in (0 ..< depth).reversed() {
      text += "\(MarkerText.sentinel)end example.nest#binding-\(index) "
    }

    return try MarkerSamples.scan(text)
  }

  @Test(arguments: [5000, 15000, 30000])
  func `blank regions nested deep are all empty and each carries its one warning`(
    depth: Int,
  ) throws {
    let scan = try scanBlankNest(depth: depth)
    let allEmpty = scan.regions.allSatisfy(\.isEmpty)

    #expect(scan.regions.count == depth)
    #expect(allEmpty)
    #expect(scan.diagnostics.count == depth)
  }

  @Test
  func `thirty thousand same-line regions on one line are all found`() throws {
    let pair = "/* \(MarkerText.sentinel)example.row#cell */ v "
      + "/* \(MarkerText.sentinel)end example.row#cell */ "
    let text = String(repeating: pair, count: 30000) + "\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.count == 30000)
    #expect(scan.regions.allSatisfy { $0.startLine == 1 })
  }

  @Test(arguments: [100_000, 5_000_000])
  func `a very long line is no problem`(length: Int) throws {
    let longLine = String(repeating: "x", count: length)
    let text = "// \(MarkerSamples.open)\n\(longLine)\n// \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(region.lines == 2 ... 2)
    #expect(region.byteRange.count == length + 1)
    #expect(!region.isEmpty)
  }

  @Test
  func `a very long blank line is an empty region`() throws {
    let text = "// \(MarkerSamples.open)\n\(String(repeating: " ", count: 1_000_000))\n"
      + "// \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.first?.isEmpty == true)
    #expect(scan.diagnostics.count == 1)
  }

  @Test
  func `a very long same-line region is no problem`() throws {
    let long = String(repeating: "y", count: 2_000_000)
    let text = "\(MarkerSamples.open) \(long) \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.first?.byteRange.count == 2_000_002)
    #expect(scan.regions.first?.isEmpty == false)
  }

  @Test
  func `a file of sentinel-free lines is scanned to its end and has nothing to say`() throws {
    let text = String(repeating: "let value = 1 // nothing to see\n", count: 100_000)

    let scan = try MarkerSamples.scan(text)

    #expect(scan == .nothing)
  }
}
