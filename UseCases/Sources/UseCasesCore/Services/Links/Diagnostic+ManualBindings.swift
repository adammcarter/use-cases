/// What a manual binding has to say about itself, with its wording in one place (chapter 08
/// "Manual bindings", chapter 09 §20.1). A binding that does not resolve is filed under the
/// definition file that writes it; a warning about a link that does is filed under the file it
/// links, at the line it starts on.
extension Diagnostic {
  /// A manual binding that does not resolve: INVALID.
  static func unresolvedBinding(
    _ problem: ManualBindingProblem,
    identity: LinkIdentity,
    path: WorkspacePath,
    definedIn definition: WorkspacePath,
  ) -> Diagnostic {
    let words = description(
      of: problem,
      path: path,
    )

    return Diagnostic(
      file: definition,
      position: nil,
      code: words.code,
      severity: .error,
      message: "\(identity.subject) \(words.message)",
    )
  }

  /// A link that resolved into a path discovery excludes: allowed, with a warning.
  static func pointsAtExcludedContent(
    _ link: ResolvedLink,
    because exclusion: ExclusionMatch,
  ) -> Diagnostic {
    located(
      link.path,
      line: link.startLine,
      code: .linkIntoExcludedContent,
      severity: .warning,
      message: "the link points at excluded content: \(link.identity.subject) names this "
        + "file, which \(exclusion.subject) leaves out of the scan",
    )
  }

  /// A whole-file binding of an empty file.
  static func emptyWholeFileBinding(_ link: ResolvedLink) -> Diagnostic {
    located(
      link.path,
      line: link.startLine,
      code: .emptyWholeFileBinding,
      severity: .warning,
      message: "empty whole-file binding: \(link.identity.subject) names an empty file",
    )
  }

  /// A range that selects no bytes.
  static func emptyBindingRange(_ link: ResolvedLink) -> Diagnostic {
    located(
      link.path,
      line: link.startLine,
      code: .emptyBindingRange,
      severity: .warning,
      message: "empty range: \(link.identity.subject) selects no bytes, as its end column is "
        + "one less than its start column",
    )
  }

  private static func description(
    of problem: ManualBindingProblem,
    path: WorkspacePath,
  ) -> (code: DiagnosticCode, message: String) {
    switch problem {
    case let .path(error):
      description(
        of: error,
        path: path,
      )
    case let .notAFile(kind):
      (
        .bindingFileNotAFile,
        "names '\(path)', which is \(kind == .directory ? "a folder" : "a pipe, socket or device")"
          + ", not a file",
      )
    case let .unreadable(error):
      (.bindingFileUnreadable, "names '\(path)', which cannot be read: \(error)")
    case let .range(error):
      description(
        of: error,
        path: path,
      )
    }
  }

  private static func description(
    of error: ExactPathError,
    path: WorkspacePath,
  ) -> (code: DiagnosticCode, message: String) {
    switch error {
    case .missing:
      (.bindingFileMissing, "names '\(path)', which is missing")
    case let .spelledDifferently(written, onDisk):
      (
        .bindingFileSpelledDifferently,
        "names '\(path)', but '\(written)' is spelled '\(onDisk)' on disk; paths must match "
          + "exactly, case and Unicode form included",
      )
    case let .behindSymlink(link):
      (
        .bindingFileBehindSymlink,
        "names a path that cannot be followed: '\(path)' passes through '\(link)', a symlink, "
          + "which is never followed",
      )
    case let .unreadableFolder(folder, reason):
      (
        .bindingFileUnreadable,
        "names '\(path)', but the folder '\(folder)' cannot be read: \(reason)",
      )
    }
  }

  private static func description(
    of error: ManualRangeError,
    path: WorkspacePath,
  ) -> (code: DiagnosticCode, message: String) {
    switch error {
    case .notText:
      (
        .bindingRangeNotText,
        "has a range, but '\(path)' is not text (strict UTF-8) and a range can only be cut "
          + "from text; bind the whole file instead",
      )
    case let .lineOutsideFile(line, lineCount):
      (
        .bindingRangeOutsideFile,
        "has a range that reaches line \(line), but '\(path)' \(lines(lineCount))",
      )
    case let .startColumnOutsideLine(column, line, length):
      (
        .bindingRangeOutsideFile,
        "has start column \(column) on line \(line) of '\(path)', but a start column there is "
          + "from 1 to \(length + 1)",
      )
    case let .endColumnOutsideLine(column, line, length):
      (
        .bindingRangeOutsideFile,
        "has end column \(column) on line \(line) of '\(path)', but "
          + (length == 0
            ? "that line is empty, so no end column fits"
            : "an end column there is from 1 to \(length)"),
      )
    case .startsAfterEnd:
      (.bindingRangeOutsideFile, "has a range that starts after it ends in '\(path)'")
    }
  }

  private static func lines(_ count: Int) -> String {
    switch count {
    case 0:
      "is empty"
    case 1:
      "has 1 line"
    default:
      "has \(count) lines"
    }
  }
}
