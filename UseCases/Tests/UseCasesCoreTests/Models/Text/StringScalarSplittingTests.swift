import Testing
@testable import UseCasesCore

struct StringScalarSplittingTests {
  @Test(
    arguments: [
      ("a/b", ["a", "b"]),
      ("", [""]),
      ("/", ["", ""]),
      ("a//b", ["a", "", "b"]),
      ("/a/", ["", "a", ""]),
      ("no-separator", ["no-separator"]),
      ("a/\u{301}b", ["a", "\u{301}b"]),
      ("a\r\n/b", ["a\r\n", "b"]),
    ],
  )
  func `splits on every separator and keeps empty pieces`(
    text: String,
    expected: [String],
  ) {
    let pieces = text.splitOnScalar("/")

    #expect(scalars(of: pieces) == scalars(of: expected))
  }

  private func scalars(of texts: [String]) -> [[Unicode.Scalar]] {
    var result: [[Unicode.Scalar]] = []

    for text in texts {
      result.append(Array(text.unicodeScalars))
    }

    return result
  }
}
