/// A use case of a loaded workspace, with the provenance chapter 09 §18 asks for.
struct LoadedUseCase: Equatable, Sendable {
  /// The full id: scope prefixes, the file's prefix and the local id (chapter 09 §10).
  let identifier: UseCaseIdentifier

  /// The definition file it is written in.
  let file: WorkspacePath

  /// The folder of the scope that owns the file.
  let scope: WorkspacePath

  /// The use case as written, with its defaults filled in; its local id is in it.
  let definition: UseCaseDefinition
}
