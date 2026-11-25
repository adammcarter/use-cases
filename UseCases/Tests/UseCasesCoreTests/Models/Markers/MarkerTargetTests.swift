import Testing
@testable import UseCasesCore

struct MarkerTargetTests {
  @Test
  func `an implementation marker names a use case and a binding`() throws {
    let target = try MarkerTarget(parsing: "app.auth.login.authenticate#authenticate-request")

    #expect(target.useCase.text == "app.auth.login.authenticate")
    #expect(target.route == nil)
    #expect(target.binding.text == "authenticate-request")
    #expect(target.text == "app.auth.login.authenticate#authenticate-request")
  }

  @Test
  func `a validation marker names a use case, a route and a binding`() throws {
    let target = try MarkerTarget(
      parsing: "app.auth.login.authenticate#unit-tests.valid-credentials",
    )

    #expect(target.useCase.text == "app.auth.login.authenticate")
    #expect(target.route?.text == "unit-tests")
    #expect(target.binding.text == "valid-credentials")
    #expect(target.description == "app.auth.login.authenticate#unit-tests.valid-credentials")
  }

  @Test(arguments: ["a#b", "3d#v2", "renderer.3d.preview#ipv6", "a-b.c#d-e.f-g", "a#9"])
  func `ids made of valid segments are read and written back unchanged`(text: String) throws {
    #expect(try MarkerTarget(parsing: text).text == text)
  }

  @Test(
    arguments: [
      ("", MarkerTargetError.empty),
      ("a", .missingSeparator),
      ("app.login", .missingSeparator),
      ("a#b#c", .severalSeparators),
      ("#", .invalidUseCase(.empty)),
      ("a#b.c.d", .tooManyPiecesAfterSeparator),
      ("a#.b", .invalidRoute(.empty)),
      ("a#b.", .invalidBinding(.empty)),
      ("a#", .invalidBinding(.empty)),
      ("#b", .invalidUseCase(.empty)),
      ("a..b#c", .invalidUseCase(.emptySegment(within: "a..b"))),
      (".a#b", .invalidUseCase(.emptySegment(within: ".a"))),
      ("A#b", .invalidUseCase(.invalidCharacter("A", within: "A"))),
      ("a#B", .invalidBinding(.invalidCharacter("B", within: "B"))),
      ("a#B.c", .invalidRoute(.invalidCharacter("B", within: "B"))),
      ("-a#b", .invalidUseCase(.leadingHyphen(within: "-a"))),
      ("a#b-", .invalidBinding(.trailingHyphen(within: "b-"))),
      ("a#-b", .invalidBinding(.leadingHyphen(within: "-b"))),
      ("a-.b#c", .invalidUseCase(.trailingHyphen(within: "a-.b"))),
    ] as [(String, MarkerTargetError)],
  )
  func `an id off the marker grammar is refused, saying why`(
    text: String,
    expected: MarkerTargetError,
  ) {
    #expect(throws: expected) {
      try MarkerTarget(parsing: text)
    }
  }

  @Test
  func `every refusal says what is wrong in words`() {
    let errors: [MarkerTargetError] = [
      .empty, .missingSeparator, .severalSeparators, .tooManyPiecesAfterSeparator,
      .emptyBeforeWord("BAD"), .runsIntoWord("T"), .invalidUseCase(.empty),
      .invalidRoute(.empty), .invalidBinding(.empty),
    ]

    for error in errors {
      #expect(!error.description.isEmpty)
    }
  }
}
