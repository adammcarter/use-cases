import Testing
@testable import UseCasesCore

struct WordDistanceTests {
  private let distance = WordDistance()

  private func between(
    _ first: String,
    _ second: String,
    atMost limit: Int = 2,
  ) -> Int? {
    distance.between(
      Array(first),
      Array(second),
      atMost: limit,
    )
  }

  @Test(arguments: [
    ("photo", "photo", 0),
    ("photo", "phto", 1),
    ("photo", "photoo", 1),
    ("photo", "phoxo", 1),
    ("phtoo", "photo", 1),
    ("photo", "phtoos", 2),
    ("abcd", "badc", 2),
    ("", "ab", 2),
    ("ab", "", 2),
  ])
  func `a wrong, missing, extra or swapped letter is one typo`(
    first: String,
    second: String,
    expected: Int,
  ) {
    #expect(between(first, second) == expected)
  }

  @Test(arguments: [
    ("photo", "photography", 1),
    ("abc", "xyz", 2),
    ("abcdef", "abc", 2),
    ("abc", "", 2),
  ])
  func `words further apart than the limit are not close`(
    first: String,
    second: String,
    limit: Int,
  ) {
    #expect(between(first, second, atMost: limit) == nil)
  }

  @Test
  func `the limit is inclusive`() {
    #expect(between("photo", "phto", atMost: 1) == 1)
    #expect(between("photo", "pto", atMost: 1) == nil)
  }
}
