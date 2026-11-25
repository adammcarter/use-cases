import Testing
@testable import UseCasesCore

struct UseCaseInputCheckerTests {
  private let checker = UseCaseInputChecker()

  private func input(_ members: [(String, AuthoredValue)]) -> AuthoredInput {
    AuthoredInput(
      name: "stdin",
      value: .object(
        members.map { key, value in
          AuthoredMember(
            key: key,
            value: value,
          )
        },
      ),
    )
  }

  @Test
  func `a use case with its full id is read with its own id`() throws {
    let checked = try checker.check(
      input([
        ("id", .string("shop.login.lockout")),
        ("title", .string("Lock out")),
      ]),
    )

    #expect(checked.identifier.text == "shop.login.lockout")
    #expect(checked.definition.localIdentifier.text == "lockout")
    #expect(checked.definition.title == "Lock out")
  }

  @Test(arguments: [
    AuthoredValue.array([]),
    .string("shop.login.x"),
    .null,
    .object([]),
    .object([AuthoredMember(key: "id", value: .integer(4))]),
    .object([AuthoredMember(key: "title", value: .string("No id"))]),
  ])
  func `anything but one mapping with an id is not a use case`(value: AuthoredValue) {
    #expect(throws: UseCaseEditingError.notAUseCase(name: "stdin")) {
      try checker.check(AuthoredInput(name: "stdin", value: value))
    }
  }

  @Test
  func `an id that is not an id is refused with the reason`() {
    #expect(throws: UseCaseEditingError.self) {
      try checker.check(input([("id", .string("Shop.Login")), ("title", .string("T"))]))
    }
  }

  @Test(arguments: [
    ("runner", AuthoredValue.string("swift"), "runner"),
    ("value_tier", .string("urgent"), "urgent"),
    ("nonsense", .boolean(true), "nonsense"),
  ])
  func `a field a use case file refuses is refused, and its name is in the message`(
    field: String,
    value: AuthoredValue,
    word: String,
  ) throws {
    let error = try #require(
      #expect(throws: UseCaseEditingError.self) {
        try checker.check(
          input([
            ("id", .string("shop.login.x")),
            ("title", .string("T")),
            (field, value),
          ]),
        )
      },
    )

    #expect(error.message.contains(word))
    #expect(error.kind == .invalid)
  }

  @Test
  func `a route that covers a scenario the use case does not have is refused`() throws {
    let error = try #require(
      #expect(throws: UseCaseEditingError.self) {
        try checker.check(
          input([
            ("id", .string("shop.login.x")),
            ("title", .string("T")),
            (
              "validation",
              .array([
                .object([
                  AuthoredMember(key: "id", value: .string("r")),
                  AuthoredMember(key: "type", value: .object([
                    AuthoredMember(key: "kind", value: .string("unit")),
                  ])),
                  AuthoredMember(key: "covers", value: .array([.string("nope")])),
                ]),
              ]),
            ),
          ]),
        )
      },
    )

    #expect(error.message.contains("nope"))
  }
}
