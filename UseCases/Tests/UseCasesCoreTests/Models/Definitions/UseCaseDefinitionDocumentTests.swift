import Testing
@testable import UseCasesCore

struct UseCaseDefinitionDocumentTests {
  private static let digest = String(repeating: "a", count: 64)

  private static let everything = """
  prefix: a
  use_cases:
    - id: login
      title: Log in
      description: People sign in.
      value_tier: critical
      intent: A person gets in.
      out_of_scope: [single sign-on]
      scenarios:
        - id: valid
          given: [An account.]
          when: [They sign in.]
          then: [They are in.]
      validation:
        - id: unit-tests
          type: { kind: custom, name: style-check }
          covers: [valid]
          gates_verification: false
          procedure:
            setup: [Start.]
            steps: [Look.]
            reset: [Stop.]
          bindings:
            - id: script
              kind: manual
              locator:
                file: scripts/check.sh
                start: { line: 1, column: 2 }
                end: { line: 3 }
          resources:
            - { kind: file, path: fixtures/a.json }
            - { kind: glob, pattern: "fixtures/**/*.json" }
      bindings:
        - id: whole
          kind: manual
          locator: { file: src/login.swift }
      approved:
        by: ada
        "on": "2026-01-02"
        behaviour: "
  """ + digest + "\"\n"

  private static let route = """
  {"bindings":[{"id":"script","kind":"manual","locator":{"end":{"line":3},\
  "file":"scripts/check.sh","start":{"column":2,"line":1}}}],"covers":["valid"],\
  "gates_verification":false,"id":"unit-tests",\
  "procedure":{"reset":["Stop."],"setup":["Start."],"steps":["Look."]},\
  "resources":[{"kind":"file","path":"fixtures/a.json"},\
  {"kind":"glob","pattern":"fixtures/**/*.json"}],"type":{"kind":"custom","name":"style-check"}}
  """

  private static let scenario = """
  {"given":["An account."],"id":"valid","then":["They are in."],"when":["They sign in."]}
  """

  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  private func document(of definitions: String) throws -> String {
    try fixture.write("use-cases/a.yml", definitions)
    let useCase = try #require(fixture.loaded().useCases.first)

    return StoreJSONWriter().compact(
      useCase.definition.document(identifier: useCase.identifier),
    ).utf8Text
  }

  @Test
  func `a use case with every field is written whole, with its full id`() throws {
    let text = try document(of: Self.everything)

    let expected = [
      "{\"approved\":{\"behaviour\":\"" + Self.digest + "\",\"by\":\"ada\",",
      "\"on\":\"2026-01-02\"},",
      "\"bindings\":[{\"id\":\"whole\",\"kind\":\"manual\",",
      "\"locator\":{\"file\":\"src/login.swift\"}}],",
      "\"description\":\"People sign in.\",\"id\":\"app.a.login\",",
      "\"intent\":\"A person gets in.\",\"out_of_scope\":[\"single sign-on\"],",
      "\"scenarios\":[" + Self.scenario + "],",
      "\"title\":\"Log in\",\"validation\":[" + Self.route + "],\"value_tier\":\"critical\"}",
    ].joined()

    #expect(text == expected)
  }

  @Test
  func `a use case with only what it must have leaves everything else out`() throws {
    let text = try document(
      of: "prefix: a\nuse_cases:\n  - id: wip\n    title: Work in progress\n",
    )

    #expect(text == "{\"id\":\"app.a.wip\",\"title\":\"Work in progress\"}")
  }

  @Test
  func `the id is written as given, the full id or the local one`() throws {
    try fixture.write(
      "use-cases/a.yml",
      "prefix: a\nuse_cases:\n  - id: wip\n    title: Work in progress\n",
    )
    let useCase = try #require(fixture.loaded().useCases.first)

    let local = StoreJSONWriter().compact(useCase.definition.document(writing: "wip")).utf8Text
    let full = StoreJSONWriter().compact(
      useCase.definition.document(identifier: useCase.identifier),
    ).utf8Text

    #expect(local == "{\"id\":\"wip\",\"title\":\"Work in progress\"}")
    #expect(full == "{\"id\":\"app.a.wip\",\"title\":\"Work in progress\"}")
  }

  @Test(
    arguments: [
      "unit", "integration", "contract", "snapshot", "ui", "e2e", "acceptance", "performance",
    ],
  )
  func `each built-in kind of route is written as it is authored`(kind: String) throws {
    let text = try document(
      of: "prefix: a\nuse_cases:\n  - id: wip\n    title: Work\n    scenarios:\n"
        + "      - id: s\n        when: [x]\n        then: [y]\n    validation:\n"
        + "      - id: route\n        type: { kind: " + kind + " }\n        covers: [s]\n",
    )

    #expect(text.contains("\"type\":{\"kind\":\"" + kind + "\"}"))
    #expect(!text.contains("gates_verification"))
  }
}
