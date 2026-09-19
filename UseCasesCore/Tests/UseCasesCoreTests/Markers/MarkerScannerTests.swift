import Testing
@testable import UseCasesCore

/// Built at runtime so this source file never contains a line the repository's
/// own marker scan would read as a real binding.
private let markerToken = "//: @use-" + "case:"

/// The scanner: markers found, explicit spans paired, lone starts inferred or
/// refused, and every integrity problem reported with its frozen code, in the
/// order the TypeScript reports it.
struct MarkerScannerTests {
  @Test(arguments: MarkersGoldenCorpus.scanFileCaseNames)
  func `scans a file to exactly the TypeScript result`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "scan_file")
    let expected = try #require(entry["result"])

    let result = try MarkerScanner.scanFile(
      filePath: MarkersFixtures.string(entry, "path"),
      contents: MarkersFixtures.string(entry, "contents"),
      configuration: MarkersFixtures.configuration(entry),
    )

    #expect(MarkersFixtures.wire(result.jsonValue) == MarkersFixtures.wire(expected))
  }

  @Test(arguments: MarkersGoldenCorpus.scanFileCaseNames)
  func `each binding's byte range and report match the TypeScript`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "scan_file")
    let contents = try MarkersFixtures.string(entry, "contents")
    let result = try MarkerScanner.scanFile(
      filePath: MarkersFixtures.string(entry, "path"),
      contents: contents,
      configuration: MarkersFixtures.configuration(entry),
    )
    let slices = try MarkersFixtures.strings(entry, "byte_slices")
    let reports = try #require(entry["reports"]?.arrayValue)

    try #require(result.bindings.count == slices.count)
    for (index, binding) in result.bindings.enumerated() {
      let span = binding.span
      #expect(try MarkersFixtures.byteSlice(contents, start: span.startByte, end: span.endByte)
        == slices[index])
      #expect(MarkerScanner.formatInferredSwiftSpanReport(binding) == reports[index].stringValue)
    }
  }

  @Test(arguments: MarkersGoldenCorpus.scanFilesCaseNames)
  func `scans many files to exactly the TypeScript result`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "scan_files")
    let expected = try #require(entry["result"])
    let inputs = try #require(entry["inputs"]?.arrayValue).map { input in
      try ScanInput(
        filePath: MarkersFixtures.string(input, "file_path"),
        contents: MarkersFixtures.string(input, "contents"),
      )
    }

    let result = MarkerScanner.scanFiles(
      inputs,
      configuration: MarkersFixtures.configuration(entry),
    )

    #expect(MarkersFixtures.wire(result.jsonValue) == MarkersFixtures.wire(expected))
  }

  @Test
  func `a nested span suppresses both bindings`() {
    let contents = """
    \(markerToken)a.outer
    \(markerToken)a.inner
    \(markerToken)end a.inner
    \(markerToken)end a.outer
    """

    let result = MarkerScanner.scanFile(filePath: "f.ts", contents: contents)

    #expect(result.bindings.isEmpty)
    #expect(result.errors.map(\.code.rawValue) == ["NESTED_SPAN"])
  }

  @Test
  func `adjacent markers report an end line one before the start line`() throws {
    let contents = "//: @use-case:a.b\n//: @use-case:end a.b\n"

    let result = MarkerScanner.scanFile(filePath: "f.ts", contents: contents)

    let binding = try #require(result.bindings.first)
    #expect(binding.span.startLine == 2)
    #expect(binding.span.endLine == 1)
    #expect(binding.span.startByte == 18)
    #expect(binding.span.endByte == 18)
  }

  @Test
  func `an explicit binding prints no inferred span report`() throws {
    let contents = "//: @use-case:a.b\nx\n//: @use-case:end a.b"
    let result = MarkerScanner.scanFile(filePath: "f.swift", contents: contents)

    let binding = try #require(result.bindings.first)
    #expect(MarkerScanner.formatInferredSwiftSpanReport(binding) == nil)
  }
}
