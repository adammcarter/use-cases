/// Why a link a links transformer returned cannot stand (chapter 10 §11): a transformer is
/// trusted for nothing, so every link must name a real place.
enum TransformerLinkProblem: Error, Equatable, Sendable {
  /// A member every link needs is not there.
  case missingMember(String)

  /// A `role` that is neither `implementation` nor `validation`.
  case unknownRole(String)

  /// The use case is not one of the workspace's.
  case unknownUseCase(String)

  /// A `binding` off the id grammar.
  case invalidBinding(String)

  /// A validation link names no route.
  case validationNeedsRoute

  /// An implementation link names a route.
  case implementationHasRoute(String)

  /// The use case has no such route.
  case unknownRoute(
    route: String,
    useCase: String,
  )

  /// A `file` that is not a path inside the workspace.
  case fileOutsideProject(WorkspacePathError)

  /// A `file` that discovery leaves out, so it is not scanned (chapter 04).
  case fileExcluded(ExclusionMatch)

  /// The file is not there as spelled, is not a file, or cannot be read.
  case file(
    ManualBindingProblem,
    path: WorkspacePath,
  )

  /// A `range` that is not two lines counted from 1.
  case rangeNotLines

  /// A range that is not inside the file.
  case range(
    ManualRangeError,
    path: WorkspacePath,
  )
}
