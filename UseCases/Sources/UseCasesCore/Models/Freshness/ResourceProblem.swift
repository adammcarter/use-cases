/// Why a route's resource cannot be resolved (chapter 09 §20.2): the workspace is INVALID.
enum ResourceProblem: Equatable, Sendable {
  /// An explicit file path that is not a file there, as it is spelled.
  case file(
    WorkspacePath,
    ExactPathError,
  )

  /// A resource file that is there but cannot be taken as a file's bytes.
  case content(
    WorkspacePath,
    FileContentError,
  )

  /// A glob that no file the code scan reads matches.
  case matchesNothing(PathPattern)
}
