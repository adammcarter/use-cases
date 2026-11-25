import Testing
@testable import UseCasesCore

struct StrictYAMLReaderSourceTests {
  private let reader = StrictYAMLReader()

  @Test(arguments: ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
  func `a refusal's line is right whichever line break the file uses`(lineBreak: String) throws {
    let text = "a: 1\(lineBreak)b: 2\(lineBreak)c: !!str x\(lineBreak)"

    let error = try #require(reader.attempt(text).failure)

    #expect(error == .tagged(YAMLLocation(file: "use-cases/a.yml", line: 3)))
  }

  @Test(arguments: ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
  func `a comment is found whichever line break the file uses`(lineBreak: String) throws {
    let text = "a: 1\(lineBreak)b: two words # note\(lineBreak)c: 3\(lineBreak)"

    let error = try #require(reader.attempt(text).failure)

    #expect(error == .textCutByComment(
      YAMLLocation(file: "use-cases/a.yml", line: 2),
      text: "two words",
      comment: "# note",
    ))
  }

  @Test(arguments: ["\n", "\r\n", "\r"])
  func `a file reads the same whichever line break it uses`(lineBreak: String) {
    let text = ["a: 1", "b:", "  - x", "  - |", "    y", "c: \"z\"", ""]
      .joined(separator: lineBreak)

    #expect(reader.attempt(text).success == .members([
      "a": .integer(1),
      "b": .array([.string("x"), .string("y\n")]),
      "c": .string("z"),
    ]))
  }

  @Test
  func `columns past multi-byte text still line up`() throws {
    let text = "caf\u{E9}: \u{1F600}\u{1F600} \u{1F600}\nb: !!str x\n"

    let error = try #require(reader.attempt(text).failure)

    #expect(error.line == 2)
  }

  @Test
  func `a long list reads in order`() {
    var text = ""
    var expected: [AuthoredValue] = []

    for number in 0 ..< 5000 {
      text += "- item \(number)\n"
      expected.append(.string("item \(number)"))
    }

    #expect(reader.attempt(text).success == .array(expected))
  }

  @Test
  func `a list nested to the limit reads`() {
    let depth = 64
    let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)

    var expected = AuthoredValue.array([])

    for _ in 1 ..< depth {
      expected = .array([expected])
    }

    #expect(reader.attempt(text).success == expected)
  }
}
