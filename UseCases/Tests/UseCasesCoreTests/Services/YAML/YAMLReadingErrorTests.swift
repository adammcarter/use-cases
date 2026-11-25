import Testing
@testable import UseCasesCore

struct YAMLReadingErrorTests {
  private let location = YAMLLocation(
    file: "use-cases/a.yml",
    line: 17,
  )

  @Test
  func `every message starts with the file and the line`() {
    let errors: [YAMLReadingError] = [
      .malformed(location, problem: "p"),
      .multipleDocuments(location),
      .tagged(location),
      .undefinedAlias(location),
      .duplicateKey(location, key: "title"),
      .unquoted(
        location,
        text: "on",
        problem: .readDifferently(yaml11: .boolean(true), yaml12: .text),
      ),
      .unquoted(location, text: "99999999999999999999", problem: .integerTooLarge),
      .unquoted(location, text: ".inf", problem: .notJSONNumber),
      .unquoted(location, text: "1", problem: .keyNotText(.integer(1))),
      .limitExceeded(location, .nesting(maximum: 64)),
      .limitExceeded(location, .aliasValues(maximum: 100_000)),
      .limitExceeded(location, .values(maximum: 100_000)),
      .textCutByComment(location, text: "a", comment: "# b"),
      .unusableKey(location),
      .leadingByteOrderMark(location),
      .unquoted(location, text: "x?", problem: .questionMarkInFlow),
    ]

    for error in errors {
      #expect(error.message.hasPrefix("use-cases/a.yml:17: "))
      #expect(error.line == 17)
      #expect(error.location == location)
    }
  }

  @Test
  func `a question mark in a list on one line says what and to quote it`() {
    let error = YAMLReadingError.unquoted(location, text: "x?", problem: .questionMarkInFlow)

    #expect(error.message == "use-cases/a.yml:17: 'x?' has a '?' in a list or mapping written on "
      + "one line, which YAML readers read differently; quote it")
  }

  @Test
  func `a text that starts with a byte order mark says what and why`() {
    let error = YAMLReadingError.leadingByteOrderMark(location)

    #expect(error.message.contains("byte order mark (U+FEFF)"))
    #expect(error.message.contains("YAML readers drop it"))
  }

  @Test
  func `a second document is called a single document rule`() {
    #expect(YAMLReadingError.multipleDocuments(location).message.contains("single document"))
  }

  @Test
  func `a tag is called a tag`() {
    #expect(YAMLReadingError.tagged(location).message.contains("tag"))
  }

  @Test
  func `a duplicate key is named`() {
    let error = YAMLReadingError.duplicateKey(location, key: "title")

    #expect(error.message == "use-cases/a.yml:17: duplicate key 'title'")
  }

  @Test
  func `an ambiguous scalar says how each version reads it and to quote it`() {
    let error = YAMLReadingError.unquoted(
      location,
      text: "017",
      problem: .readDifferently(
        yaml11: .integer(.exact(15)),
        yaml12: .integer(.exact(17)),
      ),
    )

    #expect(
      error.message == "use-cases/a.yml:17: '017' reads as the integer 15 in YAML 1.1 "
        + "and as the integer 17 in YAML 1.2; quote it",
    )
  }

  @Test
  func `a comment that cuts text names both and says how to fix it`() {
    let error = YAMLReadingError.textCutByComment(
      location,
      text: "Check medal",
      comment: "#4 shows",
    )

    #expect(error.message.contains("use-cases/a.yml:17: 'Check medal' is followed by '#4 shows'"))
    #expect(error.message.contains("quote the whole text"))
    #expect(error.message.contains("on its own line"))
  }

  @Test
  func `a number too big is named and the fix is given`() {
    let error = YAMLReadingError.unquoted(
      location,
      text: "99999999999999999999",
      problem: .integerTooLarge,
    )

    #expect(error.message.contains("'99999999999999999999'"))
    #expect(error.message.contains("too big"))
  }

  @Test(arguments: [
    (YAMLUnquotedProblem.notJSONNumber, "is a number JSON cannot hold; quote it"),
    (.keyNotText(.integer(1)), "is a plain key that reads as an integer, not text; quote it"),
    (.keyNotText(.null), "is a plain key that reads as null, not text; quote it"),
    (.keyNotText(.boolean(true)), "is a plain key that reads as a boolean, not text; quote it"),
    (.keyNotText(.number(1.5)), "is a plain key that reads as a number, not text; quote it"),
  ])
  func `an unquoted problem says what is wrong and ends by saying to quote it`(
    problem: YAMLUnquotedProblem,
    message: String,
  ) {
    #expect(problem.message == message)
  }

  @Test
  func `the alias limit message names the file, the line and the limit`() {
    let error = YAMLReadingError.limitExceeded(location, .aliasValues(maximum: 100_000))

    #expect(error.message == "use-cases/a.yml:17: aliases here expand to more than 100,000 values")
  }

  @Test(arguments: [
    (0, "0"),
    (64, "64"),
    (999, "999"),
    (1000, "1,000"),
    (100_000, "100,000"),
    (1_234_567, "1,234,567")
  ])
  func `a limit is written with thousands separators`(
    number: Int,
    written: String,
  ) {
    #expect(YAMLLimit.nesting(maximum: number)
      .message == "this is nested deeper than \(written) levels")
  }
}
