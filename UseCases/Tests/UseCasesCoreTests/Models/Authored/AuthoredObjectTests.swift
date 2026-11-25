import Testing
@testable import UseCasesCore

struct AuthoredObjectTests {
  private func object(
    _ json: String,
    at location: String = "",
  ) throws -> AuthoredObject {
    try AuthoredObject(
      authored(json),
      at: location,
    )
  }

  @Test(arguments: ["1", "[]", #""text""#, "null", "true"])
  func `a value that is not a mapping is refused`(json: String) throws {
    #expect(throws: AuthoredShapeError.notAnObject(location: "use_cases[0]")) {
      try AuthoredObject(
        authored(json),
        at: "use_cases[0]",
      )
    }
  }

  @Test
  func `a member is found by its exact UTF-8 spelling`() throws {
    let composed = "caf\u{E9}"
    let decomposed = "cafe\u{301}"
    let object = try object(JSONMembers([composed: jsonString("a")]).json)

    #expect(object.value(for: composed) == .string("a"))
    #expect(object.value(for: decomposed) == nil)
  }

  @Test
  func `a member's place is the mapping's place and its key`() throws {
    let whole = try object("{}")
    let inList = try object(
      "{}",
      at: "use_cases[2]",
    )
    let nested = try object(
      "{}",
      at: "validation[0].type",
    )

    #expect(whole.location(of: "title") == "title")
    #expect(inList.location(of: "title") == "use_cases[2].title")
    #expect(nested.location(of: "kind") == "validation[0].type.kind")
  }

  @Test
  func `a required string that is missing or of another type is refused`() throws {
    let object = try object(#"{"title":4}"#, at: "use_cases[0]")

    #expect(throws: AuthoredShapeError.missing(location: "use_cases[0].id")) {
      try object.requiredString("id")
    }
    #expect(
      throws: AuthoredShapeError.wrongType(
        location: "use_cases[0].title",
        expected: "text",
      ),
    ) {
      try object.requiredString("title")
    }
  }

  @Test
  func `an optional string that is absent is nil and one of another type is refused`() throws {
    let object = try object(#"{"intent":true}"#)

    #expect(try object.optionalString("description") == nil)
    #expect(throws: AuthoredShapeError.self) {
      try object.optionalString("intent")
    }
  }

  @Test(arguments: [#"{"n":1.5}"#, #"{"n":"1"}"#, #"{"n":null}"#, "{}"])
  func `a required integer must be a whole number`(json: String) throws {
    let object = try object(json)

    #expect(throws: AuthoredShapeError.self) {
      try object.requiredInteger("n")
    }
  }

  @Test(arguments: [(#"{"n":40.0}"#, 40), (#"{"n":1e2}"#, 100), (#"{"n":-3}"#, -3)])
  func `a whole number written with a fraction or exponent is a whole number`(
    case example: (json: String, expected: Int),
  ) throws {
    let object = try object(example.json)

    #expect(try object.requiredInteger("n") == example.expected)
  }

  @Test
  func `a position's line may be written 40.0`() throws {
    let object = try object(#"{"s":{"line":40.0,"column":2.0}}"#)

    let position = try #require(try object.optionalPosition("s"))

    #expect(position.line == 40)
    #expect(position.column == 2)
  }

  @Test
  func `a list is read item by item and an absent list is empty`() throws {
    let object = try object(#"{"steps":["a","b"],"bad":["a",1]}"#)

    #expect(try object.strings("steps") == ["a", "b"])
    #expect(try object.strings("missing").isEmpty)
    #expect(
      throws: AuthoredShapeError.wrongType(
        location: "bad[1]",
        expected: "text",
      ),
    ) {
      try object.strings("bad")
    }
  }

  @Test
  func `a key that holds no list is refused where a list is read`() throws {
    let object = try object(#"{"steps":"a"}"#)

    #expect(
      throws: AuthoredShapeError.wrongType(
        location: "steps",
        expected: "a list",
      ),
    ) {
      try object.strings("steps")
    }
  }

  @Test
  func `the objects of a list carry their place`() throws {
    let object = try object(#"{"validation":[{},{}]}"#)

    let routes = try object.objects("validation")

    #expect(routes.map(\.location) == ["validation[0]", "validation[1]"])
  }

  @Test
  func `a choice must be one of the cases of its type`() throws {
    let object = try object(#"{"value_tier":"vital"}"#)

    #expect(
      throws: AuthoredShapeError.unknownChoice(
        location: "value_tier",
        text: "vital",
      ),
    ) {
      try object.requiredChoice(
        "value_tier",
        as: ValueTier.self,
      )
    }
    #expect(
      try object.optionalChoice(
        "other",
        as: ValueTier.self,
      ) == nil,
    )
  }

  @Test
  func `a list of ids is read in the order written`() throws {
    let object = try object(#"{"covers":["ok","a-1"]}"#)

    let identifiers = try object.identifiers(
      "covers",
      parsing: ScenarioIdentifier.init(validating:),
    )

    #expect(identifiers.map(\.text) == ["ok", "a-1"])
  }

  @Test
  func `a list of ids names the item that is off the grammar`() throws {
    let object = try object(#"{"covers":["ok","Bad"]}"#)

    #expect(
      throws: AuthoredShapeError.invalidIdentifier(
        location: "covers[1]",
        .invalidCharacter("B", within: "Bad"),
      ),
    ) {
      try object.identifiers(
        "covers",
        parsing: ScenarioIdentifier.init(validating:),
      )
    }
  }

  @Test
  func `a position with a line alone has no column`() throws {
    let object = try object(#"{"s":{"line":3}}"#)

    let position = try #require(try object.optionalPosition("s"))

    #expect(position.line == 3)
    #expect(position.column == nil)
  }

  @Test
  func `a position may also have a column`() throws {
    let object = try object(#"{"s":{"line":3,"column":9}}"#)

    let position = try #require(try object.optionalPosition("s"))

    #expect(position.line == 3)
    #expect(position.column == 9)
  }

  @Test(arguments: [#"{"s":{"line":0}}"#, #"{"s":{"line":1,"column":0}}"#, #"{"s":{"line":-4}}"#])
  func `a position below 1 is refused`(json: String) throws {
    let object = try object(json)

    #expect(throws: AuthoredShapeError.self) {
      try object.optionalPosition("s")
    }
  }

  @Test(arguments: ["2026-02-30", "2026-13-01", "2026-1-1", "yesterday", "0000-01-01", ""])
  func `a day that does not exist is refused`(text: String) throws {
    let object = try object(JSONMembers(["on": jsonString(text)]).json)

    #expect(
      throws: AuthoredShapeError.invalidDate(
        location: "on",
        text: text,
      ),
    ) {
      try object.requiredDay("on")
    }
  }

  @Test(arguments: ["2026-10-11", "2024-02-29", "0001-01-01"])
  func `a day that exists is accepted`(text: String) throws {
    let object = try object(JSONMembers(["on": jsonString(text)]).json)

    #expect(try object.requiredDay("on") == text)
  }

  @Test(arguments: ["/etc", "../x", "./x", "a//b", "C:x", ""])
  func `a path off the workspace grammar is refused with the path's own reason`(
    text: String,
  ) throws {
    let object = try object(JSONMembers(["file": jsonString(text)]).json)

    #expect(throws: AuthoredShapeError.self) {
      try object.requiredPath("file")
    }
  }

  @Test
  func `an omitted path takes the given default`() throws {
    let object = try object("{}")

    let path = try object.path(
      "use_cases_dir",
      defaultText: "use-cases",
    )

    #expect(path.text == "use-cases")
  }
}
