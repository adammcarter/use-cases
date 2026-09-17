import Testing
@testable import UseCasesCore

/// Rendering one card, against the exact text the TypeScript rendered for the
/// same item and result — every format, open and with each kind of result —
/// or the honesty error it threw instead.
struct PresentationCardRendererTests {
  @Test(arguments: PresentationGoldenCorpus.cardCaseNames)
  func `a card renders byte for byte as the TypeScript rendered it`(caseName: String) throws {
    let testCase = try PresentationFixtures.goldenCase(caseName, in: "cards")
    let item = try PresentationFixtures.item(testCase["item"])
    let result = try PresentationFixtures.renderResult(testCase["result"])

    let outcome = Result { () throws(PresentationError) -> String in
      try PresentationCardRenderer.renderCard(item, result: result)
    }

    if let thrown = testCase["throws"] {
      guard case let .failure(error) = outcome else {
        Issue.record("expected rendering to throw \(PresentationFixtures.wire(thrown))")
        return
      }
      #expect(error.code == thrown["code"]?.stringValue)
      #expect(error.message == thrown["message"]?.stringValue)
      return
    }
    let text = try outcome.get()
    #expect(Array(text.utf8) == Array((testCase["text"]?.stringValue ?? "").utf8))
  }

  @Test
  func `the corpus renders every format, both with and without a result, and every honesty error`(
  ) throws {
    let cases = try #require(PresentationFixtures.section("cards").arrayValue)
    let formats = Set(cases.compactMap { $0["item"]?["presentation_format"]?.stringValue })
    let codes = Set(cases.compactMap { $0["throws"]?["code"]?.stringValue })

    #expect(formats == Set(PresentationFormat.allCases.map(\.rawValue)))
    #expect(cases.contains { $0["result"] == nil && $0["text"] != nil })
    #expect(cases.contains { $0["result"] != nil && $0["text"] != nil })
    #expect(codes == [
      "live_result_not_renderable",
      "user_led_requires_human_answer",
      "pass_requires_recorded_evidence",
    ])
  }
}
