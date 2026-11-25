import Testing
@testable import UseCasesCore

struct OptionalNilFirstOrderingTests {
  @Test(arguments: [1, 0, -5, Int.min, Int.max])
  func `a missing value comes before any value`(value: Int) {
    let missing: Int? = nil

    #expect(missing.precedesNilFirst(value))
    #expect(!Optional(value).precedesNilFirst(missing))
  }

  @Test(
    arguments: [
      (1, 2),
      (-1, 0),
      (Int.min, Int.max),
    ],
  )
  func `values keep their own order`(
    smaller: Int,
    larger: Int,
  ) {
    #expect(Optional(smaller).precedesNilFirst(larger))
    #expect(!Optional(larger).precedesNilFirst(smaller))
    #expect(!Optional(smaller).precedesNilFirst(smaller))
  }

  @Test
  func `two missing values do not precede each other`() {
    let first: Int? = nil

    #expect(!first.precedesNilFirst(nil))
  }
}
