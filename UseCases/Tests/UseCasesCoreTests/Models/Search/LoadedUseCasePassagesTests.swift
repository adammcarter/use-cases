import Testing
@testable import UseCasesCore

struct LoadedUseCasePassagesTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/dark.yml",
      YAMLSamples.file(
        prefix: "dark",
        """
          - id: toggle
            title: Dark mode
            description: Switch themes.
            value_tier: core
            intent: Readable at night.
            out_of_scope: [Scheduling]
            scenarios:
              - id: on-state
                given: [It is dusk]
                when: [Tap the switch]
                then: [Dark]
            validation:
              - id: manual
                type: { kind: acceptance }
                covers: [on-state]
                procedure:
                  setup: [Open settings]
                  steps: [Check it.]
                  reset: [Close settings]\n
        """,
      ),
    )
  }

  private func passages(_ fields: Set<SearchField>) throws -> [UseCasePassage] {
    try #require(fixture.loaded().useCases.first).passages(in: fields)
  }

  @Test
  func `every field is read in the order a reader meets it, with where`() throws {
    let all = try passages(Set(SearchField.allCases))

    #expect(all.map(\.field) == [
      .id, .title, .description, .intent,
      .scenarios, .scenarios, .scenarios, .scenarios,
      .outOfScope,
      .validation, .validation, .validation, .validation,
    ])
    #expect(all.map(\.passage.text) == [
      "app.dark.toggle", "Dark mode", "Switch themes.", "Readable at night.",
      "on-state", "It is dusk", "Tap the switch", "Dark",
      "Scheduling",
      "manual", "Open settings", "Check it.", "Close settings",
    ])
    #expect(all.map(\.location) == [
      nil, nil, nil, nil,
      "on-state", "on-state", "on-state", "on-state",
      nil,
      "manual", "manual", "manual", "manual",
    ])
  }

  @Test
  func `only the fields asked for are read, each with its weight`() throws {
    let some = try passages([.title, .intent])

    #expect(some.map(\.passage.weight) == [10, 6])
  }

  @Test(arguments: [
    (SearchField.id, 10), (.title, 10), (.description, 6), (.intent, 6),
    (.scenarios, 3), (.outOfScope, 3), (.validation, 3),
  ])
  func `an id or title counts most, then description and intent, then the rest`(
    field: SearchField,
    weight: Int,
  ) {
    #expect(field.weight == weight)
  }

  @Test
  func `a draft has only what it has`() throws {
    try fixture.write(
      "use-cases/dark.yml",
      "prefix: dark\nuse_cases:\n  - id: wip\n    title: Work\n",
    )

    #expect(try passages(Set(SearchField.allCases)).map(\.passage.text) == ["app.dark.wip", "Work"])
  }
}
