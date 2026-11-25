import Testing
@testable import UseCasesCore

struct BindingIdentifierTests {
  @Test(
    arguments: [
      "a", "0", "success", "invalid-password", "oauth2-callback", "unit-tests", "3d",
      String(repeating: "x", count: 10000),
    ],
  )
  func `an id on the segment grammar is accepted`(text: String) throws {
    let identifier = try BindingIdentifier(validating: text)

    #expect(identifier.text == text)
    #expect(identifier.description == text)
  }

  @Test(
    arguments: [
      "", "-", "-a", "a-", "A", "a_b", "a b", "a.b", "a#b", "\u{E9}", "a\n", "a\r\n", "\n",
    ],
  )
  func `an id off the segment grammar is refused`(text: String) {
    #expect(throws: IdentityError.self) {
      try BindingIdentifier(validating: text)
    }
  }
}
