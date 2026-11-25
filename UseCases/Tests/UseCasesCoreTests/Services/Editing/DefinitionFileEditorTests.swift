import Testing
@testable import UseCasesCore

struct DefinitionFileEditorTests {
  private static let commented = """
  # kept
  prefix: dark
  use_cases:
    # about toggle
    - id: toggle
      title: "Dark mode" # why
      value_tier: core
      intent: Readable at night.
      scenarios:
        - id: on-state
          when: [x]
          then: [y]
      validation:
        - id: manual
          type: { kind: acceptance }
          covers: [on-state]
          procedure:
            steps: [Check it.]

    - id: other
      title: Other
  """

  private let editor = DefinitionFileEditor()
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write("use-cases/dark.yml", Self.commented + "\n")
  }

  private func definition(_ local: String) throws -> UseCaseDefinition {
    try #require(
      fixture.loaded().useCases.first { useCase in
        useCase.definition.localIdentifier.text == local
      },
    ).definition
  }

  private func text(of edited: EditedDefinitionFile) -> String {
    edited.change.text
  }

  // @use-case:edit.comments-kept#swift-tests.warned
  @Test
  func `a replaced use case drops the comments inside it and lists each, keeping those around it`(
  ) throws {
    let changed = try definition("toggle").retitled("Dark mode, changed")

    let edited = try editor.edit(
      .replace(
        UseCaseIdentifier(validating: "app.dark.toggle"),
        with: changed,
      ),
      in: fixture.loaded(),
    )
    let written = text(of: edited)

    #expect(edited.change.action == .replace)
    #expect(written
      .hasPrefix("# kept\nprefix: dark\nuse_cases:\n  # about toggle\n  - id: toggle\n"))
    #expect(written.contains("    title: Dark mode, changed\n"))
    #expect(!written.contains("# why"))
    #expect(written.hasSuffix("\n  - id: other\n    title: Other\n"))
    #expect(edited.droppedComments == [
      "use-cases/dark.yml:6: the comment # why is dropped, as app.dark.toggle is rewritten whole",
    ])
  }

  // @use-case:end edit.comments-kept#swift-tests.warned

  @Test
  func `a removed use case takes its comment above it, and says so`() throws {
    let edited = try editor.edit(
      .remove(UseCaseIdentifier(validating: "app.dark.toggle")),
      in: fixture.loaded(),
    )

    #expect(text(of: edited) ==
      "# kept\nprefix: dark\nuse_cases:\n  - id: other\n    title: Other\n")
    #expect(edited.droppedComments.count == 2)
    #expect(edited.droppedComments[0].contains(":4: the comment # about toggle"))
    #expect(edited.droppedComments[1].contains(":6: the comment # why"))
  }

  // @use-case:edit.comments-kept#swift-tests.warned
  @Test
  func `the last use case of a file takes the file with it, and every comment in it is listed`(
  ) throws {
    let edited = try editor.edit(
      .remove(UseCaseIdentifier(validating: "app.dark.other")),
      in: fixture.loaded(),
    )

    #expect(edited.change.action == .replace)

    try fixture.write(
      "use-cases/dark.yml",
      "# only\nprefix: dark\nuse_cases:\n  - id: other\n    title: Other\n",
    )
    let last = try editor.edit(
      .remove(UseCaseIdentifier(validating: "app.dark.other")),
      in: fixture.loaded(),
    )

    #expect(last.change.action == .delete)
    #expect(last.change.path == "use-cases/dark.yml")
    #expect(last.droppedComments.count == 1)
    #expect(last.droppedComments[0].contains("# only"))
  }

  // @use-case:end edit.comments-kept#swift-tests.warned

  @Test
  func `a use case is added after the last one in the file's own indentation`() throws {
    let edited = try editor.edit(
      .append(
        file: WorkspacePath(validating: "use-cases/dark.yml"),
        definition: definition("other").renamed("added"),
      ),
      in: fixture.loaded(),
    )

    #expect(text(of: edited)
      .hasSuffix("  - id: other\n    title: Other\n\n  - id: added\n    title: Other\n"))
  }

  @Test(arguments: ["on", "no", "1e3", "payments.card"])
  func `a new file starts with its prefix and the list, the prefix quoted when needed`(
    prefix: String,
  ) throws {
    let edited = try editor.edit(
      .create(
        file: WorkspacePath(validating: "use-cases/new.yml"),
        prefix: Namespace(validating: prefix),
        definition: definition("other").renamed("fresh"),
      ),
      in: fixture.loaded(),
    )
    let written = text(of: edited)

    #expect(edited.change.action == .create)
    #expect(written.hasPrefix("prefix: "))
    #expect(written.contains("\nuse_cases:\n  - id: fresh\n    title: Other\n"))
  }

  @Test
  func `a file whose use cases are not a dashed list cannot be edited, and is told so`() throws {
    try fixture.write("use-cases/flow.yml", "prefix: flow\nuse_cases: [{ id: a, title: A }]\n")

    let error = #expect(throws: UseCaseEditingError.self) {
      try editor.edit(
        .remove(UseCaseIdentifier(validating: "app.flow.a")),
        in: fixture.loaded(),
      )
    }

    #expect(error?.kind == .refused)
    #expect(error?.message.contains("use-cases/flow.yml cannot be edited by its lines") == true)
  }

  @Test
  func `an edit that would not read back as meant is refused, nothing returned`() throws {
    let broken = DefinitionFileEditor(serialiser: BrokenSerialiser())

    #expect(throws: UseCaseEditingError.wouldNotReadBack(file: "use-cases/dark.yml")) {
      try broken.edit(
        .replace(
          UseCaseIdentifier(validating: "app.dark.toggle"),
          with: definition("toggle"),
        ),
        in: fixture.loaded(),
      )
    }
  }

  @Test
  func `a use case that is not in the workspace cannot be replaced or removed`() throws {
    #expect(throws: UseCaseEditingError.unknown(identifier: "app.dark.nope")) {
      try editor.edit(
        .remove(UseCaseIdentifier(validating: "app.dark.nope")),
        in: fixture.loaded(),
      )
    }
  }
}

extension DefinitionFileEditorTests {
  private static let apostrophes = """
  prefix: quirk
  use_cases:
    - id: a
      title: A
      intent: Built in the '90s style

    # about b
    - id: b
      title: "B" # why
      intent: say "hello

    # about c
    - id: c
      title: C
  """

  private func quirky() throws -> LoadedWorkspace {
    try fixture.write("use-cases/quirk.yml", Self.apostrophes + "\n")

    return try fixture.loaded()
  }

  @Test
  func `removing a use case whose text has quote marks keeps the comment above the next one`(
  ) throws {
    let edited = try editor.edit(
      .remove(UseCaseIdentifier(validating: "app.quirk.a")),
      in: quirky(),
    )

    #expect(edited.change.text.contains("  # about b\n  - id: b\n"))
    #expect(edited.change.text.contains("  # about c\n  - id: c\n"))
    #expect(edited.droppedComments.isEmpty)
  }

  @Test
  func `replacing a use case whose text has quote marks keeps its neighbours' comments`() throws {
    let workspace = try quirky()
    let useCase = try #require(workspace.useCases.first { $0.identifier.text == "app.quirk.a" })

    let edited = try editor.edit(
      .replace(
        useCase.identifier,
        with: useCase.definition.retitled("A, changed"),
      ),
      in: workspace,
    )

    #expect(edited.change.text.contains("    title: A, changed\n"))
    #expect(edited.change.text.contains("\n\n  # about b\n  - id: b\n"))
    #expect(edited.change.text.contains("title: \"B\" # why"))
    #expect(edited.droppedComments.isEmpty)
  }

  @Test
  func `changing a use case lists its own comments when the one before it has quote marks`(
  ) throws {
    let workspace = try quirky()
    let useCase = try #require(workspace.useCases.first { $0.identifier.text == "app.quirk.b" })

    let edited = try editor.edit(
      .replace(
        useCase.identifier,
        with: useCase.definition.retitled("B, changed"),
      ),
      in: workspace,
    )

    #expect(edited.droppedComments == [
      "use-cases/quirk.yml:9: the comment # why is dropped, as app.quirk.b is rewritten whole",
    ])
    #expect(edited.change.text.contains("  # about b\n  - id: b\n"))
    #expect(edited.change.text.contains("  # about c\n  - id: c\n"))
  }

  @Test
  func `a comment indented less than a block's text is listed when its use case is rewritten`(
  ) throws {
    try fixture.write(
      "use-cases/block.yml",
      "prefix: block\nuse_cases:\n  - id: a\n    title: A\n    intent: |\n        text\n"
        + "      # real comment\n",
    )
    let workspace = try fixture.loaded()
    let useCase = try #require(workspace.useCases.first { $0.identifier.text == "app.block.a" })

    let edited = try editor.edit(
      .replace(
        useCase.identifier,
        with: useCase.definition.retitled("A, changed"),
      ),
      in: workspace,
    )

    #expect(edited.droppedComments == [
      "use-cases/block.yml:7: the comment # real comment is dropped, "
        + "as app.block.a is rewritten whole",
    ])
  }

  @Test
  func `the comment above a use case is kept when it is rewritten, and listed when it goes`(
  ) throws {
    let workspace = try fixture.loaded()
    let useCase = try #require(workspace.useCases.first { $0.identifier.text == "app.dark.toggle" })

    let replaced = try editor.edit(
      .replace(
        useCase.identifier,
        with: useCase.definition.retitled("Dark mode, changed"),
      ),
      in: workspace,
    )
    let removed = try editor.edit(
      .remove(useCase.identifier),
      in: workspace,
    )

    #expect(replaced.change.text.contains("  # about toggle\n  - id: toggle\n"))
    #expect(!replaced.droppedComments.joined(separator: "\n").contains("# about toggle"))
    #expect(!removed.change.text.contains("# about toggle"))
    #expect(
      removed.droppedComments.joined(separator: "\n").contains(":4: the comment # about toggle"),
    )
  }
}

/// A serialiser that writes a title no one sent.
private struct BrokenSerialiser: UseCaseSerialising {
  func lines(
    of definition: UseCaseDefinition,
    writing id: String,
  ) -> [String] {
    ["id: \(id)", "title: Not what was sent"]
  }

  func itemLines(
    of definition: UseCaseDefinition,
    writing id: String,
    indent: Int,
  ) -> [String] {
    ["  - id: \(id)", "    title: Not what was sent"]
  }
}

private extension UseCaseDefinition {
  func retitled(_ title: String) -> UseCaseDefinition {
    UseCaseDefinition(
      localIdentifier: localIdentifier,
      title: title,
      description: description,
      valueTier: valueTier,
      intent: intent,
      outOfScope: outOfScope,
      scenarios: scenarios,
      routes: routes,
      bindings: bindings,
      approval: approval,
    )
  }

  func renamed(_ local: String) -> UseCaseDefinition {
    UseCaseDefinition(
      localIdentifier: (try? IdentifierSegment(validating: local)) ?? localIdentifier,
      title: title,
      description: description,
      valueTier: valueTier,
      intent: intent,
      outOfScope: outOfScope,
      scenarios: scenarios,
      routes: routes,
      bindings: bindings,
      approval: approval,
    )
  }
}
