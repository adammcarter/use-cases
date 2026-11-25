import Testing
@testable import UseCasesCore

struct NormalizationRunTests {
  /// A text and what each set of rules makes of it, written out: line endings alone, whitespace
  /// alone, and both (line endings first).
  private struct Sample {
    let text: String
    let lineEndings: String
    let whitespace: String
    let both: String

    func expected(_ rules: [FreshnessNormalization]) -> String {
      switch (rules.contains(.lineEndings), rules.contains(.whitespace)) {
      case (true, true):
        both
      case (true, false):
        lineEndings
      default:
        whitespace
      }
    }
  }

  private static let samples = [
    Sample(text: "", lineEndings: "", whitespace: "", both: ""),
    Sample(text: "plain", lineEndings: "plain", whitespace: "plain", both: "plain"),
    Sample(
      text: "a\r\nb\rc\nd\n\re",
      lineEndings: "a\nb\nc\nd\n\ne",
      whitespace: "abcde",
      both: "abcde",
    ),
    Sample(text: "\r", lineEndings: "\n", whitespace: "", both: ""),
    Sample(text: "\r\n", lineEndings: "\n", whitespace: "", both: ""),
    Sample(text: "\n\r", lineEndings: "\n\n", whitespace: "", both: ""),
    Sample(text: "\r\r\n\n", lineEndings: "\n\n\n", whitespace: "", both: ""),
    Sample(
      text: "  a \t b \u{0B}\u{0C} \r\n c  ",
      lineEndings: "  a \t b \u{0B}\u{0C} \n c  ",
      whitespace: "abc",
      both: "abc",
    ),
  ]

  private static let rules: [[FreshnessNormalization]] = [
    [.lineEndings],
    [.whitespace],
    [.lineEndings, .whitespace],
  ]

  private func run(
    _ rules: [FreshnessNormalization],
    over chunks: [[UInt8]],
  ) throws -> [UInt8] {
    var run = try #require(ContentNormalizer(ignoring: rules).normalizationRun())

    return chunks.flatMap { chunk in
      run.normalize(chunk)
    }
  }

  @Test(arguments: rules)
  func `text cut in every place is normalized as it reads when it is whole`(
    rules: [FreshnessNormalization],
  ) throws {
    for sample in Self.samples {
      let bytes = Array(sample.text.utf8)
      let expected = Array(sample.expected(rules).utf8)

      for first in 0 ... bytes.count {
        let cut = try run(rules, over: [Array(bytes[..<first]), Array(bytes[first...])])

        #expect(cut == expected, "\(sample.text.debugDescription) cut at \(first)")
      }

      let singles = try run(rules, over: bytes.map { [$0] })
      #expect(singles == expected, "\(sample.text.debugDescription) a byte at a time")
    }
  }

  @Test
  func `a carriage return that ends a chunk takes the line feed that opens the next`() throws {
    let output = try run([.lineEndings], over: [Array("a\r".utf8), Array("\nb".utf8)])

    #expect(output == Array("a\nb".utf8))
  }

  @Test
  func `a line feed that opens a chunk is kept when no carriage return came before`() throws {
    let output = try run([.lineEndings], over: [Array("a".utf8), Array("\nb".utf8)])

    #expect(output == Array("a\nb".utf8))
  }

  @Test
  func `with no rule there is no run`() {
    #expect(ContentNormalizer(ignoring: []).normalizationRun() == nil)
  }
}
