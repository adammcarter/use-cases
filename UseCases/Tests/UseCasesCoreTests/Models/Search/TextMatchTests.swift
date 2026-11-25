import Testing
@testable import UseCasesCore

struct TextMatchTests {
  private func score(
    points: Int,
    terms: Int,
  ) -> Int {
    TextMatch(
      hits: [],
      points: points,
      termCount: terms,
    ).score
  }

  @Test
  func `every word exact in the heaviest field is the best score`() {
    #expect(score(points: 2000, terms: 2) == TextMatch.bestScore)
  }

  @Test(arguments: [
    (1000, 3, 3333),
    (2000, 3, 6667),
    (300, 1, 3000),
    (1, 1000, 1),
    (500, 1, 5000),
    (1, 1, 10),
  ])
  func `the score is the points over the most possible, rounded to the nearest ten-thousandth`(
    points: Int,
    terms: Int,
    expected: Int,
  ) {
    #expect(score(points: points, terms: terms) == expected)
  }

  @Test
  func `a match never scores nothing, however many words the query has`() {
    #expect(score(points: 90, terms: 200_000) == 1)
  }
}
