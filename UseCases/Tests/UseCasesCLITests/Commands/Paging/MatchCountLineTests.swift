import Testing
@testable import UseCasesCLI

struct MatchCountLineTests {
  @Test(arguments: [
    (0, 0, 0, false, "no matches"),
    (1, 0, 1, false, "1 match"),
    (3, 0, 3, false, "3 matches"),
    (3, 0, 1, true, "1 of 3 matches"),
    (3, 1, 1, true, "2 of 3 matches"),
    (45, 20, 20, true, "21–40 of 45 matches"),
    (45, 40, 5, false, "41–45 of 45 matches"),
  ])
  func `the line says how many match and where the page is`(
    total: Int,
    offset: Int,
    shown: Int,
    hasNext: Bool,
    line: String,
  ) {
    #expect(
      MatchCountLine.text(
        total: total,
        offset: offset,
        shown: shown,
        hasNext: hasNext,
      ) == line,
    )
  }
}
