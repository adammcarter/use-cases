import Testing
@testable import UseCasesCore

struct ApproverNameTests {
  @Test(arguments: [
    ("Sam", "Sam"),
    ("  Sam  ", "Sam"),
    ("\tSam Lee\n", "Sam Lee"),
    ("A", "A"),
    ("Ada Lovelace-Byron", "Ada Lovelace-Byron"),
  ])
  func `a name is trimmed and kept`(
    typed: String,
    expected: String,
  ) throws {
    #expect(try ApproverName(validating: typed).text == expected)
  }

  @Test(arguments: ["", " ", "   ", "\t\n", "\u{00A0}"])
  func `a name with nothing in it is blank`(typed: String) {
    #expect(throws: ApproverNameError.blank) {
      try ApproverName(validating: typed)
    }
  }

  @Test
  func `a name of two hundred characters is the longest there is`() throws {
    let longest = String(repeating: "a", count: ApproverName.longest)

    #expect(try ApproverName(validating: longest).text == longest)
    #expect(try ApproverName(validating: "  " + longest + "  ").text == longest)
  }

  @Test(arguments: [201, 202, 10000])
  func `a longer name is refused with how long it is`(count: Int) {
    #expect(throws: ApproverNameError.tooLong(count: count)) {
      try ApproverName(validating: String(repeating: "a", count: count))
    }
  }

  @Test
  func `characters are counted as the schema counts them, by code point`() {
    let astral = String(repeating: "\u{1F600}", count: ApproverName.longest + 1)

    #expect(throws: ApproverNameError.tooLong(count: ApproverName.longest + 1)) {
      try ApproverName(validating: astral)
    }
  }

  @Test
  func `the refusals name the option and say it names who signed off`() {
    #expect(ApproverNameError.blank.message(of: "--by").hasPrefix("--by names who signed off"))
    #expect(
      ApproverNameError.tooLong(count: 201).message(of: "--approved-by")
        .hasPrefix("--approved-by names who signed off"),
    )
    #expect(ApproverNameError.tooLong(count: 201).message(of: "--by").contains("201"))
  }
}
