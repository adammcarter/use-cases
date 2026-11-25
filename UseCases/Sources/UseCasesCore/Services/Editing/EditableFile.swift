/// A definition file read twice: as lines, to find its use cases, and as the data it holds.
struct EditableFile {
  let path: WorkspacePath
  let layout: DefinitionFileLayout
  let original: DefinitionFile

  /// What the file held when it was read, which the writer holds it to.
  let bytes: [UInt8]

  func droppedWarning(
    _ comment: FileComment,
    because reason: String,
  ) -> String {
    "\(path.text):\(comment.line): the comment \(comment.text) is dropped, as \(reason)"
  }
}
