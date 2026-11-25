import Testing
@testable import UseCasesCore

struct PathPatternSegmentTests {
  @Test
  func `two stars alone are the any-depth segment`() throws {
    #expect(try PathPatternSegment(parsing: "**", within: "**") == .anyDepth)
  }

  @Test
  func `stars, question marks and other characters become tokens in order`() throws {
    let segment = try PathPatternSegment(parsing: "a*?[", within: "a*?[")

    #expect(segment == .name([.literal("a"), .anyRun, .anyOne, .literal("[")]))
  }

  @Test(arguments: ["a**", "**a", "***", "a**b", "*.json**"])
  func `two stars inside a longer segment are refused`(text: String) {
    #expect(throws: PathPatternError.doubleStarNotWholeSegment(text, within: "x/" + text)) {
      try PathPatternSegment(parsing: text, within: "x/" + text)
    }
  }

  @Test
  func `an empty segment is refused`() {
    #expect(throws: PathPatternError.invalidPath(.empty)) {
      try PathPatternSegment(parsing: "", within: "")
    }
  }

  @Test(
    arguments: [
      ("*.json", "a.json", true),
      ("*.json", ".json", true),
      ("*.json", "a.jsonx", false),
      ("*", "", true),
      ("*", ".hidden", true),
      ("?", "", false),
      ("?", "a", true),
      ("?", "ab", false),
      ("a?c", "abc", true),
      ("a*c*e", "abcde", true),
      ("a*c*e", "abcd", false),
      ("a.b", "aXb", false),
      ("A", "a", false),
      ("caf?", "caf\u{E9}", true),
      ("caf?", "cafe\u{301}", false),
      ("caf\u{E9}", "cafe\u{301}", false),
      ("cafe\u{301}", "caf\u{E9}", false),
    ],
  )
  func `a name pattern matches the names the dialect says`(
    pattern: String,
    name: String,
    expected: Bool,
  ) throws {
    let segment = try PathPatternSegment(parsing: pattern, within: pattern)

    #expect(segment.matchesName(name) == expected)
  }

  @Test(arguments: ["", "a", "anything"])
  func `the any-depth segment is not a name pattern and fits no name`(name: String) {
    #expect(!PathPatternSegment.anyDepth.matchesName(name))
  }
}
