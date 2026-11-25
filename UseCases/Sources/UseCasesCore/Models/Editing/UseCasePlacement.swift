/// Where a use case that is not in the workspace yet is written (chapter 04 "Recommended file
/// structure", chapter 16 §14).
enum UseCasePlacement: Equatable, Sendable {
  /// The file that already holds the use case's group.
  case existing(file: WorkspacePath)

  /// A file of its own, at the path the recommended structure gives, with the group as its
  /// prefix.
  case new(
    file: WorkspacePath,
    prefix: Namespace,
  )
}
