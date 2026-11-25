/// Edits definition files one use case after another, each edit made to the files as the edits
/// before it left them (chapter 16 §14, ADR 031), and follows what the workspace holds as it
/// goes. Nothing is written, and the workspace is not loaded again between edits: a middle state
/// may be one no command could load, and only the end is checked.
protocol UseCaseEditSequencing {
  /// The workspace as the edits so far leave it.
  var workspace: LoadedWorkspace { get }

  /// What the edits so far write, in the end: a change a file, by path, held to the file as the
  /// first edit of it read it.
  var writes: WritePlan { get }

  /// Takes a use case of the workspace out.
  mutating func removing(_ useCase: LoadedUseCase) throws(UseCaseEditingError)
    -> EditedDefinitionFile

  /// Adds a use case that is not in the workspace, where the placement says.
  mutating func adding(
    _ definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    placed placement: UseCasePlacement,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile

  /// Writes a use case of the workspace again, whole.
  mutating func replacing(
    _ useCase: LoadedUseCase,
    with definition: UseCaseDefinition,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile

  /// Gives a use case of the workspace its sign-off, changing no other line of its file.
  mutating func approving(
    _ useCase: LoadedUseCase,
    with approval: Approval,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile
}
