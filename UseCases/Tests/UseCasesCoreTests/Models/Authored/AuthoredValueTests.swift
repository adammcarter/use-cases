import Testing
@testable import UseCasesCore

struct AuthoredValueTests {
  @Test
  func `an object keeps its members in authored order`() {
    let first = AuthoredMember(
      key: "title",
      value: .string("Dark mode"),
    )
    let second = AuthoredMember(
      key: "value_tier",
      value: .string("core"),
    )

    #expect(AuthoredValue.object([first, second]) != AuthoredValue.object([second, first]))
  }

  @Test
  func `an integer and a number are different values`() {
    #expect(AuthoredValue.integer(1) != AuthoredValue.number(1))
  }
}
