/// The problems the bridge settings report themselves, with their wording in one place
/// (chapter 10 §18).
extension Diagnostic {
  /// A bridge file that is there and is not a regular file.
  static func bridgeNotAFile(
    _ file: WorkspacePath,
    kind: FileEntryKind,
  ) -> Diagnostic {
    let what =
      switch kind {
      case .directory: "a folder"
      case .symlink: "a symlink"
      case .file, .other: "not a regular file"
      }

    return Diagnostic(
      error: "bridge-not-a-file",
      in: file,
      message: "the bridge settings must be a regular file, and this is \(what)",
    )
  }

  /// A bridge file that cannot be read.
  static func unreadableBridge(
    _ file: WorkspacePath,
    because error: FileSystemError,
  ) -> Diagnostic {
    Diagnostic(
      error: "unreadable-bridge",
      in: file,
      message: "the file cannot be read: \(error)",
    )
  }

  /// A bridge file below the root.
  static func bridgeBelowRoot(_ file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      error: .rootOnlySetting,
      in: file,
      message: "bridge settings are root-only: write them in the workspace root's "
        + "use-cases-bridge.yml",
    )
  }

  /// A validation id that an earlier validation has.
  static func duplicateValidation(
    _ identifier: IdentifierSegment,
    at index: Int,
    first: Int,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "duplicate-validation",
      in: file,
      message: "validation id \(AuthoredValue.quote(identifier.text)) is used more than once "
        + "(validations/\(first)/id and validations/\(index)/id); an id names one validation",
    )
  }

  /// A `report` that is a path.
  static func reportIsAPath(
    _ report: String,
    at index: Int,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "report-is-a-path",
      in: file,
      message: "report must be a file or folder name, not a path (\(AuthoredValue.quote(report)) "
        + "at validations/\(index)/report): each run gives its tests a fresh reports folder, "
        + "and {report} is the path inside it",
    )
  }

  /// A run argument with a near miss of `{report}`, such as a mistyped `{reprot}`.
  static func unknownPlaceholder(
    _ placeholder: RunPlaceholder,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "unknown-placeholder",
      in: file,
      message: "\(place): unknown placeholder \(placeholder.text); "
        + "{report} is the only one",
    )
  }

  /// A `working_dir` that is not an existing folder inside the workspace.
  static func badWorkingDirectory(
    _ directory: WorkspacePath,
    because reason: String,
    at index: Int,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "bad-working-dir",
      in: file,
      message: "working_dir must be an existing folder inside the project: "
        + "\(AuthoredValue.quote(directory.text)) \(reason) (at validations/\(index)/working_dir)",
    )
  }

  /// A bundled transformer name that no bundled transformer has.
  static func unknownBundledTransformer(
    _ name: String,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "unknown-transformer",
      in: file,
      message: "unknown bundled transformer \(AuthoredValue.quote(name)) at \(place); "
        + "a project program is named by its path from the workspace root",
    )
  }

  /// A transformer program that is missing or not inside the workspace.
  static func badTransformerProgram(
    _ program: WorkspacePath,
    because reason: String,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "bad-transformer-program",
      in: file,
      message: "transformer program \(AuthoredValue.quote(program.text)) \(reason) at \(place)",
    )
  }

  /// A `validations` that is written and empty.
  static func noValidations(in file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      warning: "no-validations",
      in: file,
      message: "validations is empty: nothing is set up to verify",
    )
  }

  /// A validation that has no `run` command.
  static func validationWithoutRun(
    _ validation: IdentifierSegment,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "validation-without-run",
      in: file,
      message: "validation \(AuthoredValue.quote(validation.text)) has no run command: it can "
        + "only be read after `verify --start`",
    )
  }

  /// A run command that names its program by an absolute path.
  static func absoluteRunCommand(
    _ executable: String,
    of validation: IdentifierSegment,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "absolute-run-command",
      in: file,
      message: "validation \(AuthoredValue.quote(validation.text)): the command "
        + "\(AuthoredValue.quote(executable)) is an absolute path, which other machines may "
        + "not have",
    )
  }
}
