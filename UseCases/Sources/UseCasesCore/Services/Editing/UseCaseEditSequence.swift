import Foundation

/// Edits definition files one use case after another, each edit made to the files as the edits
/// before it left them (chapter 16 §14, ADR 031), and follows what the workspace holds as it
/// goes. Nothing is written, and the workspace is not loaded again between edits: a middle state
/// may be one no command could load, and only the end is checked.
struct UseCaseEditSequence: UseCaseEditSequencing {
  private let fileSystem: any FileSystemReading
  private let root: URL
  private var changes = NetFileChanges()
  private var useCases: [LoadedUseCase]
  private let start: LoadedWorkspace

  /// The workspace as the edits so far leave it.
  var workspace: LoadedWorkspace {
    start.holding(useCases)
  }

  /// What the edits so far write, in the end: a change a file, by path.
  var writes: WritePlan {
    changes.net
  }

  /// - Parameters:
  ///   - workspace: The workspace as it is.
  ///   - fileSystem: What the files are read from, below the edits.
  init(
    workspace: LoadedWorkspace,
    fileSystem: any FileSystemReading = LocalFileSystem(),
  ) {
    start = workspace
    root = workspace.root
    useCases = workspace.useCases
    self.fileSystem = fileSystem
  }

  mutating func removing(_ useCase: LoadedUseCase) throws(UseCaseEditingError)
    -> EditedDefinitionFile
  {
    let edited = try edit(.remove(useCase.identifier))

    useCases.removeAll { held in
      held.identifier == useCase.identifier
    }

    return edited
  }

  mutating func adding(
    _ definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    placed placement: UseCasePlacement,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let edited: EditedDefinitionFile = switch placement {
    case let .existing(file):
      try edit(
        .append(
          file: file,
          definition: definition,
        ),
      )
    case let .new(file, prefix):
      try edit(
        .create(
          file: file,
          prefix: prefix,
          definition: definition,
        ),
      )
    }

    useCases.append(
      LoadedUseCase(
        identifier: identifier,
        file: edited.change.workspacePath,
        scope: scope(of: edited.change.workspacePath),
        definition: definition,
      ),
    )

    return edited
  }

  mutating func replacing(
    _ useCase: LoadedUseCase,
    with definition: UseCaseDefinition,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let edited = try edit(
      .replace(
        useCase.identifier,
        with: definition,
      ),
    )

    useCases = useCases.map { held in
      held.identifier == useCase.identifier
        ? LoadedUseCase(
          identifier: held.identifier,
          file: held.file,
          scope: held.scope,
          definition: definition,
        )
        : held
    }

    return edited
  }

  mutating func approving(
    _ useCase: LoadedUseCase,
    with approval: Approval,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    let edited = try edit(
      .approve(
        useCase.identifier,
        with: approval,
      ),
    )

    useCases = useCases.map { held in
      held.identifier == useCase.identifier
        ? LoadedUseCase(
          identifier: held.identifier,
          file: held.file,
          scope: held.scope,
          definition: held.definition.approved(approval),
        )
        : held
    }

    return edited
  }

  private mutating func edit(_ edit: DefinitionFileEdit) throws(UseCaseEditingError)
    -> EditedDefinitionFile
  {
    let editor = DefinitionFileEditor(
      fileSystem: PlannedFileSystem(
        base: fileSystem,
        plan: changes.standing,
        root: root,
      ),
    )
    let edited = try editor.edit(
      edit,
      in: workspace,
    )

    changes.record(edited.change)

    return edited
  }

  /// The scope a definition file belongs to: the one whose use cases folder is the nearest above
  /// it, or the root's.
  private func scope(of file: WorkspacePath) -> WorkspacePath {
    if let neighbour = useCases.first(where: { held in held.file == file }) {
      return neighbour.scope
    }

    let folders = file.ancestors
    let owners = start.scopes.filter { scope in
      folders.contains(scope.discovered.useCasesDirectory)
    }

    let nearest = owners.max { lhs, rhs in
      lhs.discovered.useCasesDirectory.segments.count
        < rhs.discovered.useCasesDirectory.segments.count
    }

    return nearest?.discovered.directory ?? .root
  }
}
