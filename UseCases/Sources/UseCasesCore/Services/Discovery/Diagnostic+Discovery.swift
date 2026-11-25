/// The problems discovery reports, with their wording in one place.
extension Diagnostic {
  /// A folder that could not be listed.
  static func unreadableDirectory(
    _ directory: WorkspacePath,
    because error: FileSystemError,
  ) -> Diagnostic {
    problem(
      file: directory,
      code: "unreadable-directory",
      message: "the folder cannot be searched: \(error)",
    )
  }

  /// A name on disk that no workspace path can spell, so it is left out.
  static func unspellableName(
    _ name: String,
    in directory: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      file: directory,
      position: nil,
      code: "unspellable-name",
      severity: .warning,
      message: "\(name) is skipped: its name holds a character "
        + "that no workspace path can spell",
    )
  }

  /// The way out of a child scope that is not a scope: a file named `use-cases.yml` in build
  /// output or test data (chapter 09 §6.2). The exclusion goes in the root `use-cases.yml`,
  /// which can be written before `init`.
  static let notAScope = "if this file is not a Use Cases scope (build output, test data), "
    + "exclude its folder with discovery.exclude in the root use-cases.yml"

  /// A `use-cases.yml` that could not be read or is not valid scope settings. A refusal of a
  /// file below the root ends with the way out; the root's own file is the workspace itself, so
  /// it has none.
  static func configuration(
    _ configuration: WorkspacePath,
    refused error: ScopeSettingsLoadingError,
  ) -> [Diagnostic] {
    let rootFile = WorkspacePath.root.appending(literal: DiscoveredScope.configurationFileName)
    let isRootFile = configuration == rootFile

    return refusals(configuration, refused: error).map { found in
      guard !isRootFile else {
        return found
      }

      return Diagnostic(
        file: found.file,
        position: found.position,
        code: found.code,
        severity: found.severity,
        message: "\(found.message); \(notAScope)",
      )
    }
  }

  private static func refusals(
    _ configuration: WorkspacePath,
    refused error: ScopeSettingsLoadingError,
  ) -> [Diagnostic] {
    switch error {
    case let .unreadable(reason):
      [
        problem(
          file: configuration,
          code: "unreadable-configuration",
          message: "the scope's configuration cannot be read: \(reason)",
        ),
      ]
    case let .invalid(settingsError):
      settingsError.problems.map { found in
        Diagnostic(
          file: configuration,
          position: found.position,
          code: found.code,
          severity: .error,
          message: found.message,
        )
      }
    }
  }

  /// A `use-cases.yml` that is a symlink.
  static func configurationIsSymlink(_ configuration: WorkspacePath) -> Diagnostic {
    problem(
      file: configuration,
      code: "configuration-is-symlink",
      message: "'\(configuration)' is a symlink; a scope's use-cases.yml must be the file itself, "
        + "because a symlink is never followed or read",
    )
  }

  /// A file that is `use-cases.yml` only when case or Unicode form is ignored.
  static func configurationSpelledDifferently(_ found: WorkspacePath) -> Diagnostic {
    problem(
      file: found,
      code: "configuration-spelled-differently",
      message: "'\(found)' is not spelled use-cases.yml, so it is not a scope's configuration; "
        + "a scope's file must be named exactly use-cases.yml, case and Unicode form included",
    )
  }

  /// A definition file whose ending is not spelt in lower case.
  static func uppercaseEnding(
    _ file: WorkspacePath,
    renamed: String,
  ) -> Diagnostic {
    problem(
      file: file,
      code: "definition-ending-not-lower-case",
      message: "'\(file)' ends in a YAML ending that is not spelt in lower case; "
        + "rename it to '\(renamed)'",
    )
  }

  /// A symlink inside a `use_cases_dir`.
  static func symlinkInDefinitions(_ link: WorkspacePath) -> Diagnostic {
    problem(
      file: link,
      code: "symlink-in-definitions",
      message: "'\(link)' is a symlink inside a use_cases_dir; a symlink is never followed and "
        + "every YAML entry there must be a use case definition, so replace it with the "
        + "file itself or remove it",
    )
  }

  /// A scope whose `use-cases.yml` sits inside another scope's `use_cases_dir`.
  static func scopeInsideDefinitions(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
    owner: WorkspacePath,
  ) -> Diagnostic {
    let holder =
      owner.isRoot ? "the root scope's definitions" : "the definitions of scope '\(owner)'"

    return problem(
      file: configuration,
      code: "scope-inside-definitions",
      message: "'\(configuration)' sits inside the use_cases_dir '\(definitions)', which holds "
        + "\(holder); a scope belongs beside that folder, never inside it",
    )
  }

  /// A `use_cases_dir` that holds its own scope's `use-cases.yml`.
  static func definitionsHoldConfiguration(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
  ) -> Diagnostic {
    problem(
      file: configuration,
      code: "definitions-hold-configuration",
      message: "use_cases_dir '\(definitions)' must not contain this scope's own use-cases.yml; "
        + "name a folder below the scope",
    )
  }

  /// A `use_cases_dir` inside a tree that discovery excludes.
  static func definitionsExcluded(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
    by match: ExclusionMatch,
  ) -> Diagnostic {
    problem(
      file: configuration,
      code: "definitions-excluded",
      message: "use_cases_dir '\(definitions)' is excluded by \(match.subject), so none of its "
        + "files could be found",
    )
  }

  /// An exclusion that covers something inside a `use_cases_dir`, which is read whole.
  static func exclusionInsideDefinitions(
    _ path: WorkspacePath,
    definitions: WorkspacePath,
    by match: ExclusionMatch,
  ) -> Diagnostic {
    problem(
      file: path,
      code: "exclusion-inside-definitions",
      message: "\(match.subject) reaches inside use_cases_dir '\(definitions)' and excludes "
        + "'\(path)'; a use_cases_dir is read whole",
    )
  }

  /// A `use_cases_dir` spelt differently from the folder on disk, in case or Unicode form.
  static func definitionsSpelledDifferently(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
    written: String,
    onDisk: [String],
  ) -> Diagnostic {
    let names = onDisk
      .sorted { lhs, rhs in
        lhs.precedesExactly(rhs)
      }
      .map(\.debugDescription)

    return problem(
      file: configuration,
      code: "definitions-spelled-differently",
      message: "use_cases_dir '\(definitions)': '\(written)' is not found as written; on disk: "
        + names.joined(separator: ", "),
    )
  }

  /// A socket, pipe or device with a YAML name inside a `use_cases_dir`.
  static func notAFileInDefinitions(_ entry: WorkspacePath) -> Diagnostic {
    problem(
      file: entry,
      code: "not-a-file-in-definitions",
      message: "'\(entry)' is not a regular file (a pipe, socket or device) inside a "
        + "use_cases_dir, where every YAML entry must be a use case definition; it is never opened",
    )
  }

  /// A name inside a `use_cases_dir` that no workspace path can spell.
  static func unspellableNameInDefinitions(
    _ name: String,
    in directory: WorkspacePath,
  ) -> Diagnostic {
    problem(
      file: directory,
      code: "unspellable-name-in-definitions",
      message: "\(name) inside a use_cases_dir has a name that no workspace "
        + "path can spell, so it can be neither read nor skipped; rename it",
    )
  }

  /// A folder with an unspellable name that holds a scope.
  static func scopeInUnspellableFolder(
    _ name: String,
    in directory: WorkspacePath,
  ) -> Diagnostic {
    problem(
      file: directory,
      code: "scope-in-unspellable-folder",
      message: "\(name) holds a use-cases.yml but its name is one that no "
        + "workspace path can spell, so the scope cannot be read; rename the folder",
    )
  }

  /// A `use_cases_dir` that is, or sits behind, a symlink.
  static func definitionsBehindSymlink(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
    link: WorkspacePath,
  ) -> Diagnostic {
    problem(
      file: configuration,
      code: "definitions-behind-symlink",
      message: "use_cases_dir '\(definitions)' goes through the symlink '\(link)', which is "
        + "never followed",
    )
  }

  /// A `use_cases_dir` that names something other than a folder.
  static func definitionsNotAFolder(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
  ) -> Diagnostic {
    problem(
      file: configuration,
      code: "definitions-not-a-folder",
      message: "use_cases_dir '\(definitions)' exists and is not a folder",
    )
  }

  /// A `use_cases_dir` that is, or lies inside, another scope's, so a definition there would
  /// have two owners.
  static func definitionsOverlap(
    _ configuration: WorkspacePath,
    definitions: WorkspacePath,
    other: WorkspacePath,
    otherDefinitions: WorkspacePath,
  ) -> Diagnostic {
    let holder = other.isRoot ? "the root scope" : "the scope '\(other)'"

    return problem(
      file: configuration,
      code: "definitions-overlap",
      message: "use_cases_dir '\(definitions)' is, or is inside, the use_cases_dir "
        + "'\(otherDefinitions)' of \(holder), so a definition there would belong to two scopes",
    )
  }

  private static func problem(
    file: WorkspacePath,
    code: DiagnosticCode,
    message: String,
  ) -> Diagnostic {
    Diagnostic(
      file: file,
      position: nil,
      code: code,
      severity: .error,
      message: message,
    )
  }
}
