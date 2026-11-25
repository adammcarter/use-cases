/// A definition file as an edit leaves it.
struct EditedDefinitionFile: Equatable, Sendable {
  /// What the plan does to the file, with the bytes it will hold.
  let change: FileChange

  /// The comments the edit cannot keep, one line each.
  let droppedComments: [String]
}
