import Testing
@testable import UseCasesCore

struct UseCaseSerialiserTests {
  private static let digest = String(repeating: "a", count: 64)

  /// The `discounts` use case of `fixtures/python/2-use-cases/use-cases/billing.yml`, as a
  /// person wrote it there.
  private static let discounts = """
    - id: discounts
      title: Discounts never make a total negative
      value_tier: core
      intent: A discount larger than the invoice brings it to zero, never below.
      scenarios:
        - id: capped-at-zero
          given: [A 3.00 invoice.]
          when: [A 5.00 fixed discount is applied.]
          then: [The total is 0.00.]
      validation:
        - id: unit-tests
          type: { kind: unit }
          covers: [capped-at-zero]
      bindings:
        - id: discount-rules
          kind: manual
          locator: { file: src/invoicing/discounts.py }

  """

  private static let everything = """
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
            - kind: file
              path: fixtures/a.json
            - kind: glob
              pattern: fixtures/**/*.json
      bindings:
        - id: whole
          kind: manual
          locator: { file: src/login.swift }
      approved:
        by: ada
        "on": "2026-01-02"
        behaviour: \(digest)

  """

  private let serialiser = UseCaseSerialiser()
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  /// The use case of a definition file holding only `text`, and the lines of the item as the
  /// file has them.
  private func lines(
    of item: String,
    writing id: String,
  ) throws -> (written: [String], inFile: [String]) {
    try fixture.write("use-cases/a.yml", "prefix: a\nuse_cases:\n" + item)
    let useCase = try #require(fixture.loaded().useCases.first)
    let inFile = item.split(
      separator: "\n",
      omittingEmptySubsequences: true,
    ).map(String.init)

    return (
      serialiser.lines(
        of: useCase.definition,
        writing: id,
      ),
      inFile,
    )
  }

  /// The lines of an item as the file has them, less the two spaces `use_cases` indents them by.
  private func withoutMargin(_ lines: [String]) -> [String] {
    lines.map { line in
      String(line.dropFirst(2))
    }
  }

  /// A definition file's lines for an item, as `save` places them: a dash and a space before
  /// the first, two spaces before the others.
  private func asItem(_ lines: [String]) -> [String] {
    lines.enumerated().map { index, line in
      (index == 0 ? "- " : "  ") + line
    }
  }

  @Test
  func `a use case reads back as the lines a person wrote in the fixture`() throws {
    let lines = try lines(
      of: Self.discounts,
      writing: "discounts",
    )

    #expect(asItem(lines.written) == withoutMargin(lines.inFile))
  }

  @Test
  func `every field is written in the order people read them, the approval last`() throws {
    let lines = try lines(
      of: Self.everything,
      writing: "login",
    )

    #expect(asItem(lines.written) == withoutMargin(lines.inFile))
  }

  @Test
  func `the id is written as given, and nothing else changes with it`() throws {
    let local = try lines(
      of: Self.discounts,
      writing: "discounts",
    ).written
    let full = try lines(
      of: Self.discounts,
      writing: "invoicing.billing.discounts",
    ).written

    #expect(local.first == "id: discounts")
    #expect(full.first == "id: invoicing.billing.discounts")
    #expect(Array(local.dropFirst()) == Array(full.dropFirst()))
  }

  @Test
  func `a use case with only what it must have is two lines`() throws {
    let written = try lines(
      of: "  - id: wip\n    title: Work in progress\n",
      writing: "a.wip",
    ).written

    #expect(written == ["id: a.wip", "title: Work in progress"])
  }

  @Test
  func `a list too wide for its line is a block, a text is never wrapped`() throws {
    let written = try lines(
      of: """
        - id: wide
          title: Wide
          scenarios:
            - id: s
              when:
                - Compare TAX_RATES with the current published rates for each region.
                - Record pass if every rate matches.
              then: [Done.]

      """,
      writing: "wide",
    ).written

    #expect(written == [
      "id: wide",
      "title: Wide",
      "scenarios:",
      "  - id: s",
      "    when:",
      "      - Compare TAX_RATES with the current published rates for each region.",
      "      - Record pass if every rate matches.",
      "    then: [Done.]",
    ])
  }

  // Mutant: blank lines of a literal block given the margin of the item.
  @Test
  func `an item has a dash first and the others under it, and blank lines stay empty`() throws {
    try fixture.write(
      "use-cases/a.yml",
      """
      prefix: a
      use_cases:
        - id: wip
          title: Work
          intent: |+
            One.

            Two.


      """,
    )
    let useCase = try #require(fixture.loaded().useCases.first)

    let item = serialiser.itemLines(
      of: useCase.definition,
      writing: "wip",
      indent: 2,
    )

    #expect(item == [
      "  - id: wip",
      "    title: Work",
      "    intent: |+",
      "      One.",
      "",
      "      Two.",
      "",
    ])
  }

  @Test(arguments: [0, 2, 4])
  func `the dash sits where it is asked to`(indent: Int) throws {
    try fixture.write("use-cases/a.yml", "prefix: a\nuse_cases:\n  - id: wip\n    title: Work\n")
    let useCase = try #require(fixture.loaded().useCases.first)
    let margin = String(repeating: " ", count: indent)

    #expect(
      serialiser.itemLines(
        of: useCase.definition,
        writing: "wip",
        indent: indent,
      ) == [margin + "- id: wip", margin + "  title: Work"],
    )
  }

  @Test
  func `text of several lines is written the way people write it by hand`() throws {
    try fixture.write(
      "use-cases/a.yml",
      """
      prefix: a
      use_cases:
        - id: wip
          title: Work
          intent: |-
            One.
            Two.
          out_of_scope:
            - |
              A.
              B.
            - Plain.

      """,
    )
    let useCase = try #require(fixture.loaded().useCases.first)

    #expect(
      serialiser.lines(
        of: useCase.definition,
        writing: "wip",
      ) == [
        "id: wip", "title: Work", "intent: |-", "  One.", "  Two.", "out_of_scope:", "  - |",
        "    A.", "    B.", "  - Plain.",
      ],
    )
  }
}
