import Testing
@testable import UseCasesCore

struct TechnicalFieldCheckerTests {
  private let checker = TechnicalFieldChecker()

  /// `runner` (chapter 01 and 02) and the list of chapter 06 "Where running lives", written out.
  private static let chapterSixFields = [
    "runner", "command", "arguments", "environment", "timeout", "retries", "parallel", "batch",
  ]

  private func check(_ json: String) throws -> [Diagnostic] {
    try checker.check(
      authored(json),
      file: workspacePath("use-cases/login.yml"),
    )
  }

  private func file(
    useCase: JSONMembers = DefinitionSamples.useCase,
  ) -> String {
    DefinitionSamples.file(useCase)
  }

  @Test
  func `a file that names no code or tools has no diagnostic`() throws {
    #expect(try check(file()).isEmpty)
  }

  @Test(arguments: Self.chapterSixFields)
  func `a technical field on a use case is refused, naming the field`(field: String) throws {
    let found = try check(file(useCase: DefinitionSamples.useCase.setting(field, "[]")))

    let diagnostic = try #require(found.first)
    #expect(found.count == 1)
    #expect(diagnostic.code == .technicalField)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.message.contains("names code or tools"))
    #expect(diagnostic.message.contains("`\(field)`"))
    #expect(diagnostic.message.hasPrefix("use case 'authenticate' writes"))
    #expect(diagnostic.message.hasSuffix("not in a use case"))
  }

  @Test(arguments: Self.chapterSixFields)
  func `a technical field on a route is refused, naming the field and the route`(
    field: String,
  ) throws {
    let route = DefinitionSamples.route.setting(field, #"{"executable":"swift"}"#)
    let found = try check(
      file(useCase: DefinitionSamples.useCase.setting("validation", "[\(route.json)]")),
    )

    let diagnostic = try #require(found.first)
    #expect(found.count == 1)
    #expect(diagnostic.message.contains("names code or tools"))
    #expect(diagnostic.message.contains("`\(field)`"))
    #expect(
      diagnostic.message
        .hasPrefix("validation route 'unit-tests' of use case 'authenticate' writes"),
    )
    #expect(diagnostic.message.hasSuffix("not in a validation route"))
  }

  @Test
  func `it reads the file as written, so it finds a field the schema would also refuse`() throws {
    let json = file(useCase: DefinitionSamples.useCase.setting("runner", "[]"))
    let value = try authored(json)
    let failures = try BundledSchemaLoader().loadChecker(for: .useCases).check(value)

    #expect(!failures.isEmpty)
    #expect(try check(json).count == 1)
  }

  @Test
  func `every technical field in the file is found, in a sorted report`() throws {
    let route = DefinitionSamples.route.setting("timeout", "5")
    let useCase = DefinitionSamples.useCase
      .setting("runner", "{}")
      .setting("validation", "[\(route.json)]")

    let found = try check(file(useCase: useCase))

    #expect(found.count == 2)
    #expect(found == found.sorted())
  }

  @Test
  func `a technical field is told apart by its exact spelling`() throws {
    let useCase = DefinitionSamples.useCase
      .setting("Runner", "[]")
      .setting("run", "[]")

    #expect(try check(file(useCase: useCase)).isEmpty)
  }

  @Test(arguments: ["{}", "[]", "1", #"{"use_cases":1}"#, #"{"use_cases":[1,"a",null]}"#])
  func `what is not the shape of a definition file is left to the schema`(json: String) throws {
    #expect(try check(json).isEmpty)
  }

  @Test
  func `a use case or a route with no readable id is named by its number`() throws {
    let found = try check(
      #"{"use_cases":[{"runner":1,"validation":[{"command":1}]}]}"#,
    )
    let messages = found.map(\.message)

    #expect(messages.count == 2)
    #expect(messages.contains { message in
      message.hasPrefix("use case number 1 writes `runner`")
    })
    #expect(messages.contains { message in
      message.hasPrefix("validation route number 1 of use case number 1 writes `command`")
    })
  }
}
