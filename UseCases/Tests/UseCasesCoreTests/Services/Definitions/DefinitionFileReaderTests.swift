import Testing
@testable import UseCasesCore

struct DefinitionFileReaderTests {
  private let reader = DefinitionFileReader()

  private static func route(covering scenarios: [String]) -> JSONMembers {
    DefinitionSamples.route(
      id: "unit-tests",
      covers: scenarios,
    )
  }

  private func read(
    _ json: String,
    schemaChecked: Bool = true,
  ) throws -> DefinitionFile {
    let value = try schemaChecked
      ? checked(
        json,
        against: .useCases,
      )
      : authored(json)

    return try reader.read(
      value,
      file: workspacePath("use-cases/login.yml"),
    )
  }

  private func diagnostics(
    _ json: String,
    schemaChecked: Bool = true,
  ) throws -> [Diagnostic] {
    do {
      _ = try read(
        json,
        schemaChecked: schemaChecked,
      )
    } catch let DefinitionFileReadingError.invalid(diagnostics) {
      return diagnostics
    }

    return []
  }

  @Test
  func `a file keeps its prefix and its use cases in the order written`() throws {
    let file = try read(
      DefinitionSamples.file(
        prefix: "payments.card",
        DefinitionSamples.draft.setting("id", #""zeta""#),
        DefinitionSamples.useCase,
        DefinitionSamples.draft.setting("id", #""alpha""#),
      ),
    )

    #expect(file.prefix?.text == "payments.card")
    #expect(file.useCases.map(\.localIdentifier.text) == ["zeta", "authenticate", "alpha"])
  }

  @Test
  func `a file with no prefix has none`() throws {
    let file = try read(DefinitionSamples.file(DefinitionSamples.draft))

    #expect(file.prefix == nil)
  }

  @Test
  func `a DRAFT and a READY use case both become models`() throws {
    let file = try read(
      DefinitionSamples.file(
        DefinitionSamples.draft,
        DefinitionSamples.useCase,
      ),
    )

    #expect(
      file.useCases.map(\.authoredState)
        == [.draft(missing: [.valueTier, .intent, .scenarios, .validation]), .ready],
    )
  }

  @Test
  func `the pieces of a full id are the models' own`() throws {
    let file = try read(DefinitionSamples.file(prefix: "login", DefinitionSamples.useCase))
    let useCase = try #require(file.useCases.first)

    let identifier = try UseCaseIdentifier(
      scopePrefixes: [Namespace(validating: "shop"), Namespace(validating: "auth")],
      filePrefix: file.prefix,
      localIdentifier: useCase.localIdentifier,
    )

    #expect(identifier.text == "shop.auth.login.authenticate")
  }

  @Test
  func `a route that covers an unknown scenario makes the file INVALID`() throws {
    let found = try diagnostics(
      DefinitionSamples.file(
        DefinitionSamples.useCase.setting(
          "validation",
          "[\(Self.route(covering: ["valid-credentials", "subtracts"]).json)]",
        ),
      ),
    )

    #expect(found.count == 1)
    #expect(found.first?.message.contains("covers unknown scenarios ['subtracts']") == true)
    #expect(found.first?.file.text == "use-cases/login.yml")
    #expect(found.first?.position == nil)
  }

  @Test
  func `every problem of every use case is reported together, sorted`() throws {
    let twice = "[\(DefinitionSamples.scenario.json),\(DefinitionSamples.scenario.json)]"
    let found = try diagnostics(
      DefinitionSamples.file(
        DefinitionSamples.useCase.setting("scenarios", twice),
        DefinitionSamples.useCase
          .setting("id", #""other""#)
          .setting(
            "validation",
            "[\(DefinitionSamples.route(id: "unit-tests", covers: ["nope"]).json)]",
          ),
      ),
    )

    #expect(found.map(\.code) == [.duplicateScenario, .unknownScenario])
    #expect(found == found.sorted())
  }

  @Test
  func `a broken use case does not hide the problems of the others`() throws {
    let found = try diagnostics(
      DefinitionSamples.file(
        DefinitionSamples.draft.setting("id", #""Bad_Id""#),
        DefinitionSamples.useCase.setting(
          "validation",
          "[\(DefinitionSamples.route(id: "unit-tests", covers: ["nope"]).json)]",
        ),
      ),
      schemaChecked: false,
    )

    #expect(found.map(\.code).sorted() == [.invalidValue, .unknownScenario])
  }

  @Test
  func `a use case that cannot be read is named by its id, or else its number`() throws {
    let found = try diagnostics(
      DefinitionSamples.file(
        DefinitionSamples.draft.setting("id", #""Bad_Id""#),
        DefinitionSamples.draft.removing("id"),
      ),
      schemaChecked: false,
    )

    let messages = found.map(\.message).sorted()
    #expect(messages.count == 2)
    #expect(messages.contains { message in
      message.hasPrefix("use case 'Bad_Id': id:")
    })
    #expect(messages.contains { message in
      message.hasPrefix("use case number 2: id: this is required")
    })
  }

  @Test
  func `a prefix off the grammar is refused`() throws {
    let found = try diagnostics(
      DefinitionSamples.file(
        prefix: "Login.Page",
        DefinitionSamples.draft,
      ),
      schemaChecked: false,
    )

    #expect(found.count == 1)
    #expect(found.first?.message.hasPrefix("prefix:") == true)
  }

  @Test(arguments: ["{}", "[]", "1", #"{"use_cases":{}}"#, #"{"use_cases":[1]}"#])
  func `a file that is not a list of use cases is refused`(json: String) throws {
    let found = try diagnostics(
      json,
      schemaChecked: false,
    )

    #expect(!found.isEmpty)
    #expect(found.allSatisfy { $0.code == .invalidValue })
  }

  @Test
  func `reading twice gives the same file`() throws {
    let json = DefinitionSamples.file(
      prefix: "login",
      DefinitionSamples.useCase,
      DefinitionSamples.draft,
    )

    #expect(try read(json) == read(json))
  }
}
