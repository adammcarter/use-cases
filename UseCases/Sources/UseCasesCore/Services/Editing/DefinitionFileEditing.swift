/// Changes one use case in the lines of a definition file, and nothing else in it (chapter 16
/// §14).
protocol DefinitionFileEditing: Sendable {
  /// The file as the edit leaves it, checked: read back, it holds exactly the use cases it should.
  ///
  /// - Parameters:
  ///   - edit: What to do.
  ///   - workspace: The workspace as it is.
  /// - Throws: ``UseCaseEditingError`` when the file cannot be read or edited by its lines, or
  ///   would not read back as it should.
  func edit(
    _ edit: DefinitionFileEdit,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile
}
