import Testing
@testable import UseCasesCore

struct AuthoredValueCountingTests {
  @Test(arguments: [
    (AuthoredValue.null, 1),
    (.string("a"), 1),
    (.array([]), 1),
    (.object([]), 1),
    (.array([.integer(1), .integer(2)]), 3),
    (.members(["a": .integer(1)]), 3),
    (.members(["a": .array([.string("x"), .members(["b": .null])])]), 7),
  ])
  func `a value counts itself, every item, and every key`(
    value: AuthoredValue,
    count: Int,
  ) {
    #expect(value.valueCount == count)
  }
}
