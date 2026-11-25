import Testing
@testable import UseCasesCore

struct RunIdentifierTests {
  @Test(arguments: [
    "0000000000000000000000000000002a",
    "00000000000000000000000000000001",
    "ffffffffffffffffffffffffffffffff",
    "018f1234abcd5678ef0123456789abcd",
  ])
  func `a run id is 32 lowercase hex digits`(text: String) throws {
    #expect(try RunIdentifier(validating: text).text == text)
  }

  @Test(arguments: [
    ("", RunIdentifierError.wrongLength("")),
    ("2a", .wrongLength("2a")),
    ("0000000000000000000000000000002", .wrongLength("0000000000000000000000000000002")),
    ("000000000000000000000000000000002a", .wrongLength("000000000000000000000000000000002a")),
    ("0000000000000000000000000000002A", .notLowercaseHex("0000000000000000000000000000002A")),
    ("0000000000000000000000000000002g", .notLowercaseHex("0000000000000000000000000000002g")),
    ("0000000000000000000000000000002\n", .notLowercaseHex("0000000000000000000000000000002\n")),
    ("00000000000000000000000000000000", .reserved),
  ])
  func `anything else is refused`(
    text: String,
    expected: RunIdentifierError,
  ) {
    #expect(throws: expected) {
      try RunIdentifier(validating: text)
    }
  }

  @Test
  func `fixed width text orders as the number does`() throws {
    let ids = try [
      "0000000000000000000000000000002a",
      "000000000000000000000000000000ff",
      "00000000000000000000000000000100",
      "ffffffffffffffffffffffffffffffff",
    ].map { text in
      try RunIdentifier(validating: text)
    }

    #expect(ids == ids.sorted())
    #expect(ids[0] < ids[1])
    #expect(ids[1] < ids[2])
    #expect(ids[2] < ids[3])
  }

  @Test
  func `an error says what is wrong`() {
    #expect(RunIdentifierError.reserved.description == "the all-zero run id is reserved")
    #expect(RunIdentifierError.wrongLength("x").description.contains("32 characters"))
    #expect(RunIdentifierError.notLowercaseHex("X").description.contains("lowercase"))
  }
}
