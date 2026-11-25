extension TransformerLinkProblem: CustomStringConvertible {
  /// What is wrong with the link, in words that finish "… returned a bad link {…}: ".
  var description: String {
    switch self {
    case let .missingMember(name):
      "the link has no '\(name)'"
    case let .unknownRole(role):
      "the role '\(role)' is neither implementation nor validation"
    case let .unknownUseCase(useCase):
      "unknown use case '\(useCase)'"
    case let .invalidBinding(binding):
      "the binding '\(binding)' is not a valid id"
    case .validationNeedsRoute:
      "a validation link needs a route"
    case let .implementationHasRoute(route):
      "an implementation link has no route, but this one names '\(route)'"
    case let .unknownRoute(route, useCase):
      "unknown route '\(route)': use case '\(useCase)' has no such route"
    case let .fileOutsideProject(error):
      "the file must be a path inside the project: \(error)"
    case let .fileExcluded(exclusion):
      "the file is in an excluded folder: \(exclusion.subject) leaves it out of the scan"
    case let .file(problem, path):
      Self.words(
        of: problem,
        path: path,
      )
    case .rangeNotLines:
      "the range needs a start and an end, each a line counted from 1"
    case let .range(error, path):
      Self.words(
        of: error,
        path: path,
      )
    }
  }

  private static func words(
    of problem: ManualBindingProblem,
    path: WorkspacePath,
  ) -> String {
    switch problem {
    case let .path(error):
      words(
        of: error,
        path: path,
      )
    case let .notAFile(kind):
      "'\(path)' is \(kind == .directory ? "a folder" : "a pipe, socket or device"), not a file"
    case let .unreadable(error):
      "'\(path)' cannot be read: \(error)"
    case let .range(error):
      words(
        of: error,
        path: path,
      )
    }
  }

  private static func words(
    of error: ExactPathError,
    path: WorkspacePath,
  ) -> String {
    switch error {
    case .missing:
      "the file '\(path)' does not exist"
    case let .spelledDifferently(written, onDisk):
      "the file '\(path)' is spelled differently on disk: '\(written)' is '\(onDisk)'; paths "
        + "must match exactly"
    case let .behindSymlink(link):
      "the file '\(path)' passes through '\(link)', a symlink, which is never followed"
    case let .unreadableFolder(folder, reason):
      "the file '\(path)' cannot be reached: the folder '\(folder)' cannot be read: \(reason)"
    }
  }

  private static func words(
    of error: ManualRangeError,
    path: WorkspacePath,
  ) -> String {
    switch error {
    case .notText:
      "a range can only be cut from text, and '\(path)' is not strict UTF-8"
    case let .lineOutsideFile(line, lineCount):
      "the range is outside the file: it reaches line \(line), but '\(path)' has "
        + (lineCount == 0 ? "no lines" : "\(lineCount) line\(lineCount == 1 ? "" : "s")")
    case .startsAfterEnd:
      "the range starts after it ends in '\(path)'"
    case .startColumnOutsideLine, .endColumnOutsideLine:
      "the range does not fit '\(path)'"
    }
  }
}
