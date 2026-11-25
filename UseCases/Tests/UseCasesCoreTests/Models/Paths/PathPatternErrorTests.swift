import Testing
@testable import UseCasesCore

struct PathPatternErrorTests {
  @Test(
    arguments: [
      (PathPatternError.invalidPath(.absolute("/x")), "'/x' is not a valid pattern", "'/'"),
      (
        .invalidPath(.notCanonical("a//b", canonical: "a/b")),
        "'a//b' is not a valid pattern",
        "write 'a/b'",
      ),
      (
        .invalidPath(.notCanonical(".", canonical: nil)),
        "'.' is not a valid pattern",
        "cannot be empty or '.'",
      ),
      (
        .doubleStarNotWholeSegment("a**", within: "x/a**"),
        "'x/a**' is not a valid pattern",
        "'**' must be a whole segment",
      ),
    ],
  )
  func `a message says it is a pattern and what is wrong with it`(
    error: PathPatternError,
    start: String,
    fragment: String,
  ) {
    #expect(error.description.hasPrefix(start))
    #expect(error.description.contains(fragment))
  }
}
