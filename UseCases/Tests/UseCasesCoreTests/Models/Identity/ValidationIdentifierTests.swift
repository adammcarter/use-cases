import Testing
@testable import UseCasesCore

struct ValidationIdentifierTests {
  @Test(
    arguments: [
      "auth-tests", "all-tests", "legacy-integration", "records", "record-1", "console", "con1",
      "com0", "com10", "lpt", "lpt0", "lpt10", "nulls", "a", String(repeating: "x", count: 10000),
    ],
  )
  func `an id on the grammar and not reserved is accepted`(text: String) throws {
    let identifier = try ValidationIdentifier(validating: text)

    #expect(identifier.text == text)
  }

  @Test(
    arguments: [
      "record", "con", "prn", "aux", "nul", "com1", "com5", "com9", "lpt1", "lpt5", "lpt9",
    ],
  )
  func `a reserved name is refused`(text: String) {
    #expect(throws: IdentityError.reserved(text)) {
      try ValidationIdentifier(validating: text)
    }
  }

  @Test(arguments: ["", "-a", "a-", "Auth", "a_b", "a.b", "record\n", "con\n"])
  func `an id off the segment grammar is refused`(text: String) {
    #expect(throws: IdentityError.self) {
      try ValidationIdentifier(validating: text)
    }
  }
}
