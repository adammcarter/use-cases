import Foundation

/// Saves a use case by changing its own lines in the file that holds it, adding it to the file
/// that holds its group, or making the file the recommended structure gives it.
public struct UseCaseSaver: UseCaseSaving {
  private let reader: any AuthoredInputReading
  private let checker: any UseCaseInputChecking
  private let placer: any UseCasePlacing
  private let editor: any DefinitionFileEditing

  /// Makes the saver.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  public init(workingDirectory: URL) {
    self.init(
      reader: AuthoredInputReader(workingDirectory: workingDirectory),
      checker: UseCaseInputChecker(),
      placer: UseCasePlacer(),
      editor: DefinitionFileEditor(),
    )
  }

  init(
    reader: any AuthoredInputReading,
    checker: any UseCaseInputChecking,
    placer: any UseCasePlacing,
    editor: any DefinitionFileEditing,
  ) {
    self.reader = reader
    self.checker = checker
    self.placer = placer
    self.editor = editor
  }

  public func plan(
    savingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange {
    let input: AuthoredInput

    do {
      input = try reader.read(AuthoredInputSource(argument: argument))
    } catch {
      throw .input(message: error.message)
    }

    let checked = try checker.check(input)
    let existing = workspace.useCases.first { useCase in
      useCase.identifier == checked.identifier
    }
    let definition = try checked.keepingApproval(of: existing)

    guard let existing else {
      return try add(
        definition,
        as: checked.identifier,
        to: workspace,
      )
    }

    guard definition != existing.definition else {
      return unchanged(
        existing,
        in: workspace,
      )
    }

    return try replace(
      existing,
      with: definition,
      in: workspace,
    )
  }

  private func add(
    _ definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    to workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange {
    let edit: DefinitionFileEdit
    let action: UseCaseChangeAction

    switch try placer.place(
      identifier,
      in: workspace,
    ) {
    case let .existing(file):
      edit = .append(
        file: file,
        definition: definition,
      )
      action = .added
    case let .new(file, prefix):
      edit = .create(
        file: file,
        prefix: prefix,
        definition: definition,
      )
      action = .created
    }

    return try change(
      edit,
      action: action,
      identifier: identifier,
      definition: definition,
      in: workspace,
    )
  }

  private func replace(
    _ existing: LoadedUseCase,
    with definition: UseCaseDefinition,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange {
    try change(
      .replace(
        existing.identifier,
        with: definition,
      ),
      action: .replaced,
      identifier: existing.identifier,
      definition: definition,
      in: workspace,
    )
  }

  private func change(
    _ edit: DefinitionFileEdit,
    action: UseCaseChangeAction,
    identifier: UseCaseIdentifier,
    definition: UseCaseDefinition,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange {
    let edited = try editor.edit(
      edit,
      in: workspace,
    )

    return UseCaseChange(
      identifier: identifier.text,
      file: edited.change.path,
      action: action,
      root: workspace.root,
      writes: WritePlan(changes: [edited.change]),
      warnings: edited.droppedComments,
      expectation: .present(
        identifier: identifier,
        file: edited.change.workspacePath,
        definition: definition,
      ),
    )
  }

  private func unchanged(
    _ existing: LoadedUseCase,
    in workspace: LoadedWorkspace,
  ) -> UseCaseChange {
    UseCaseChange(
      identifier: existing.identifier.text,
      file: existing.file.text,
      action: .unchanged,
      root: workspace.root,
      writes: WritePlan(changes: []),
      warnings: [],
      expectation: .present(
        identifier: existing.identifier,
        file: existing.file,
        definition: existing.definition,
      ),
    )
  }
}
