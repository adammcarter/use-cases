import Testing
@testable import UseCasesCore

/// Built at runtime so this source file never contains a line the repository's
/// own marker scan would read as a real binding.
private let markerToken = "//: @use-" + "case:"

/// The inferred-end Swift function recognizer. The span it proves is hashed
/// into ledgers, so it must find the SAME span as the TypeScript lexer for the
/// same source — including where the TypeScript fails closed.
struct SwiftFunctionRecognizerTests {
  private func recognize(_ entry: JSONValue) throws -> SwiftFunctionRecognition {
    try SwiftFunctionRecognizer.recognize(
      source: MarkersFixtures.string(entry, "source"),
      markerLineIndex: MarkersFixtures.integer(entry, "marker_line_index"),
      markerCommentPrefix: MarkersFixtures.optionalString(entry, "marker_comment_prefix") ?? "//",
    )
  }

  @Test(arguments: MarkersGoldenCorpus.recognizerCaseNames)
  func `recognizes exactly the result the TypeScript returns`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "recognizer")
    let expected = try #require(entry["result"])

    let recognition = try recognize(entry)

    #expect(MarkersFixtures.wire(recognition.jsonValue) == MarkersFixtures.wire(expected))
  }

  @Test(arguments: MarkersGoldenCorpus.recognizerCaseNames)
  func `a proven span covers the same bytes and hash as the TypeScript`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "recognizer")
    guard case let .recognized(span, _, bodyLines) = try recognize(entry) else {
      #expect(entry["byte_slice"] == nil)
      return
    }
    let source = try MarkersFixtures.string(entry, "source")

    #expect(try MarkersFixtures.byteSlice(source, start: span.startByte, end: span.endByte)
      == MarkersFixtures.string(entry, "byte_slice"))
    #expect(try SpanCanonicalizer.hash(bodyLines) == MarkersFixtures.string(entry, "span_sha256"))
  }

  @Test
  func `a brace inside a string does not close the body`() {
    let source = """
    \(markerToken)a.b
    func f() {
      let s = "}"
    }

    """

    let recognition = SwiftFunctionRecognizer.recognize(source: source, markerLineIndex: 0)

    guard case let .recognized(span, symbolName, _) = recognition else {
      Issue.record("expected a recognized span, got \(recognition)")
      return
    }
    #expect(symbolName == "f")
    #expect(span.startLine == 2)
    #expect(span.endLine == 4)
  }

  @Test
  func `the recognizer error codes are frozen wire strings`() {
    let codes = SwiftFunctionErrorCode.allCases.map(\.rawValue)

    #expect(codes == [
      "NO_SWIFT_PARSER",
      "SWIFT_PARSE_ERROR_IN_REGION",
      "MARKER_NOT_ADJACENT_TO_DECLARATION",
      "MARKER_INSIDE_ATTACHED_DECLARATION",
      "NEXT_NODE_NOT_FUNC",
      "FUNC_HAS_NO_BODY",
      "FUNC_BODY_HAS_NO_CLOSING_BRACE",
      "NESTED_FUNC_UNSUPPORTED",
      "CONDITIONAL_COMPILATION_IN_SPAN",
      "ANOTHER_MARKER_INSIDE_SPAN",
      "MULTIPLE_CANDIDATE_DECLARATIONS",
    ])
  }
}
