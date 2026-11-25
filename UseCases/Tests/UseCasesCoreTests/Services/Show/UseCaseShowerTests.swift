import Testing
@testable import UseCasesCore

struct UseCaseShowerTests {
  private static let draft = "  - id: wip\n    title: Work in progress\n"

  private let fixture: WorkspaceFixture
  private let shower = UseCaseShower()

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/dark.yml",
      YAMLSamples.file(
        prefix: "dark",
        YAMLSamples.useCase(),
        Self.draft,
      ),
    )
  }

  private func shown(_ identifier: String) throws -> ShownUseCase {
    try shower.show(
      identifier,
      in: fixture.loaded(),
    )
  }

  /// The use case `app.dark.toggle` signed off with this fingerprint, and then written with this
  /// title.
  private func writeApproved(
    behaviour: String,
    title: String = "Dark mode",
  ) throws {
    try fixture.write(
      "use-cases/dark.yml",
      YAMLSamples.file(
        prefix: "dark",
        YAMLSamples.useCase(
          title: title,
          extra: """
              approved:
                by: Sam
                "on": "2026-10-11"
                behaviour: "\(behaviour)"\n
          """,
        ),
      ),
    )
  }

  private func fingerprint() throws -> String {
    let useCase = try #require(fixture.loaded().useCases.first)

    return try PromiseFingerprinter().fingerprint(
      of: PromiseFingerprintInput(
        definition: useCase.definition,
        identifier: useCase.identifier,
      ),
    )
  }

  @Test
  func `a READY use case is shown whole, under its full id and the file it is written in`() throws {
    let useCase = try shown("app.dark.toggle")

    #expect(useCase.identifier == "app.dark.toggle")
    #expect(useCase.file == "use-cases/dark.yml")
    #expect(useCase.isReady)
    #expect(useCase.missing.isEmpty)
    #expect(useCase.yamlLines.first == "id: app.dark.toggle")
    #expect(useCase.yamlLines.contains("title: Dark mode"))
  }

  @Test
  func `the definition is the use case as save takes it`() throws {
    let useCase = try #require(fixture.loaded().useCases.first)

    let found = try shown("app.dark.toggle").definition

    #expect(found == useCase.definition.document(identifier: useCase.identifier))
  }

  @Test
  func `the YAML is what the serialiser writes for it`() throws {
    let useCase = try #require(fixture.loaded().useCases.first)

    let found = try shown("app.dark.toggle").yamlLines

    #expect(found == UseCaseSerialiser().lines(
      of: useCase.definition,
      writing: "app.dark.toggle",
    ))
  }

  @Test
  func `a DRAFT says what it lacks, in the words a person is told`() throws {
    let useCase = try shown("app.dark.wip")

    #expect(!useCase.isReady)
    #expect(useCase.missing == ["value_tier", "intent", "a scenario", "a validation route"])
    #expect(useCase.yamlLines == ["id: app.dark.wip", "title: Work in progress"])
  }

  @Test(arguments: [
    "app.dark", "app", "toggle", "dark.toggle", "app.dark.toggle.", "App.dark.toggle",
    "app.dark.nope", "",
  ])
  func `only a full id names a use case, never a prefix or a part of one`(
    identifier: String,
  ) {
    #expect(throws: UseCaseShowingError.unknown(identifier: identifier)) {
      try shown(identifier)
    }
  }

  @Test
  func `the refusal says there is no such use case, and that show takes a full id`() {
    let message = UseCaseShowingError.unknown(identifier: "app.dark").message

    #expect(message.contains("no use case 'app.dark'"))
    #expect(message.contains("full id"))
  }

  @Test
  func `a use case never signed off is unapproved`() throws {
    #expect(try shown("app.dark.toggle").approval == .unapproved)
  }

  @Test
  func `a use case signed off as it reads now is approved`() throws {
    try writeApproved(behaviour: String(repeating: "a", count: 64))
    let promise = try fingerprint()
    try writeApproved(behaviour: promise)

    let useCase = try shown("app.dark.toggle")

    #expect(useCase.approval == .approved)
    #expect(useCase.yamlLines.suffix(4) == [
      "approved:",
      "  by: Sam",
      "  \"on\": \"2026-10-11\"",
      "  behaviour: \"\(promise)\"",
    ])
  }

  @Test
  func `a use case whose promise changed since it was signed off is changed`() throws {
    try writeApproved(behaviour: String(repeating: "a", count: 64))
    let promise = try fingerprint()
    try writeApproved(
      behaviour: promise,
      title: "Dark mode, changed",
    )

    #expect(try shown("app.dark.toggle").approval == .changed)
  }

  @Test
  func `a promise that cannot be fingerprinted is a refusal naming the use case`() throws {
    let shower = UseCaseShower(
      fingerprinter: FailingPromiseFingerprinter(),
      serialiser: UseCaseSerialiser(),
    )

    let workspace = try fixture.loaded()

    do {
      _ = try shower.show(
        "app.dark.toggle",
        in: workspace,
      )
      Issue.record("shown")
    } catch {
      #expect(error.message.hasPrefix("the promise of app.dark.toggle could not be fingerprinted"))
    }
  }
}
