/// What fingerprinting a route has to say, with its wording in one place (chapter 09 §20.2,
/// chapter 11 §50, §83). A resource that does not resolve is filed under the definition file that
/// writes it; a link whose file cannot be read is filed under that file.
extension Diagnostic {
  /// A resource that does not resolve: INVALID.
  static func resourceProblem(
    _ problem: ResourceProblem,
    of route: RouteKey,
    definedIn definition: WorkspacePath,
  ) -> Diagnostic {
    let words = description(of: problem)

    return Diagnostic(
      file: definition,
      position: nil,
      code: words.code,
      severity: .error,
      message: "\(route.subject) has \(words.message)",
    )
  }

  /// An explicit resource file inside a path discovery excludes: allowed, with a warning. Like
  /// the warning about a binding into excluded content, it is filed under the file it names.
  static func resourceIntoExcludedContent(
    _ file: WorkspacePath,
    of route: RouteKey,
    because exclusion: ExclusionMatch,
  ) -> Diagnostic {
    located(
      file,
      line: 1,
      code: .resourceIntoExcludedContent,
      severity: .warning,
      message: "the resource points at excluded content: \(route.subject) names this file, "
        + "which \(exclusion.subject) leaves out of the scan",
    )
  }

  /// A file a link points into that cannot be read: the route's fingerprint is unknown.
  static func linkedFileUnreadable(
    _ link: ResolvedLink,
    because error: FileContentError,
  ) -> Diagnostic {
    Diagnostic(
      error: .linkedFileUnreadable,
      in: link.path,
      message: "the file \(reason(of: error)), so the fingerprint of the routes linked to it is "
        + "unknown",
    )
  }

  /// A region that no longer fits its file: the file changed since the links were resolved.
  static func linkedRegionOutsideFile(_ link: ResolvedLink) -> Diagnostic {
    Diagnostic(
      error: .linkedRegionOutsideFile,
      in: link.path,
      message: "the file changed while it was being fingerprinted: \(link.identity.subject) "
        + "no longer fits it",
    )
  }

  /// A route whose parts do not fit together.
  static func routeNotFingerprintable(
    _ route: RouteKey,
    because error: FingerprintingError,
    definedIn definition: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: .routeNotFingerprintable,
      in: definition,
      message: "\(route.subject) cannot be fingerprinted: \(error)",
    )
  }

  private static func description(
    of problem: ResourceProblem,
  ) -> (code: DiagnosticCode, message: String) {
    switch problem {
    case let .file(path, error):
      description(
        of: error,
        path: path,
      )
    case let .content(path, error):
      description(
        of: error,
        path: path,
      )
    case let .matchesNothing(pattern):
      (
        .resourceGlobMatchesNothing,
        "the resource glob '\(pattern)', which matches nothing: it matches only files the code "
          + "scan reads, never excluded paths, files Use Cases owns or nested workspaces",
      )
    }
  }

  private static func description(
    of error: ExactPathError,
    path: WorkspacePath,
  ) -> (code: DiagnosticCode, message: String) {
    switch error {
    case .missing:
      (.resourceFileMissing, "the resource file '\(path)', which is missing")
    case let .spelledDifferently(written, onDisk):
      (
        .resourceFileSpelledDifferently,
        "the resource file '\(path)', but '\(written)' is spelled '\(onDisk)' on disk; paths "
          + "must match exactly, case and Unicode form included",
      )
    case let .behindSymlink(link):
      (
        .resourceFileBehindSymlink,
        "the resource file '\(path)', which cannot be followed: it passes through '\(link)', a "
          + "symlink, which is never followed",
      )
    case let .unreadableFolder(folder, failure):
      (
        .resourceFileUnreadable,
        "the resource file '\(path)', but the folder '\(folder)' \(reason(of: failure))",
      )
    }
  }

  private static func description(
    of error: FileContentError,
    path: WorkspacePath,
  ) -> (code: DiagnosticCode, message: String) {
    switch error {
    case .missing:
      (.resourceFileMissing, "the resource file '\(path)', which is missing")
    case .notAFile:
      (.resourceFileNotAFile, "the resource file '\(path)', which \(reason(of: error))")
    case .unreadable, .changedWhileRead:
      (.resourceFileUnreadable, "the resource file '\(path)', which \(reason(of: error))")
    }
  }

  private static func reason(of error: FileContentError) -> String {
    switch error {
    case .missing:
      "is missing"
    case let .notAFile(kind):
      "is \(kind == .directory ? "a folder" : "a pipe, socket or device"), not a file"
    case let .unreadable(failure):
      reason(of: failure)
    case .changedWhileRead:
      "changed while it was read"
    }
  }

  /// Why the system refused, without the absolute location it names: the message already names
  /// the file by its workspace path.
  private static func reason(of failure: FileSystemError) -> String {
    switch failure {
    case .notFound:
      "is missing"
    case let .unreadable(_, reason):
      "cannot be read: \(reason)"
    case .notUTF8:
      "is not valid UTF-8 text"
    }
  }
}
