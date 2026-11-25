/// The problems and warnings the groups file reports, with their wording in one place
/// (chapter 03 "Diagnostics").
extension Diagnostic {
  /// A groups file that is there and is not a regular file.
  static func groupsNotAFile(
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
      error: "groups-not-a-file",
      in: file,
      message: "the groups file must be a regular file, and this is \(what)",
    )
  }

  /// A groups file below the root: one root file is all v1 has (chapter 03).
  static func groupsBelowRoot(_ file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      error: .rootOnlySetting,
      in: file,
      message: "groups are root-only: write them in the workspace root's use-case-groups.yml; "
        + "nested groups files are not part of v1",
    )
  }

  /// A groups file that cannot be read.
  static func unreadableGroups(
    _ file: WorkspacePath,
    because error: FileSystemError,
  ) -> Diagnostic {
    Diagnostic(
      error: "unreadable-groups",
      in: file,
      message: "the file cannot be read: \(error)",
    )
  }

  /// An `include` that writes nothing to select with: it would quietly mean every use case.
  static func includeSelectsNothing(
    group: IdentifierSegment,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "include-selects-nothing",
      in: file,
      message: "include selects nothing at groups/\(group.text)/include; it would mean every "
        + "use case, so leave include out to say that",
    )
  }

  /// An exact id that no use case has.
  static func noSuchUseCase(
    _ identifier: Namespace,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      error: "no-such-use-case",
      in: file,
      message: "no use case \(AuthoredValue.quote(identifier.text)) at \(place); ids select "
        + "one fully resolved use case",
    )
  }

  /// A file that defines no group.
  static func noGroups(in file: WorkspacePath) -> Diagnostic {
    Diagnostic(
      warning: "no-groups",
      in: file,
      message: "groups is empty: no group is defined",
    )
  }

  /// A selector object with nothing in it.
  static func emptySelectors(
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "empty-selectors",
      in: file,
      message: "\(place) is empty: it selects nothing",
    )
  }

  /// A selector list with nothing in it.
  static func emptySelectorList(
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "empty-selector-list",
      in: file,
      message: "\(place) is empty: it selects nothing",
    )
  }

  /// A selector written twice in one list.
  static func duplicateSelector(
    _ selector: String,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "duplicate-selector",
      in: file,
      message: "duplicate selector \(AuthoredValue.quote(selector)) at \(place)",
    )
  }

  /// A prefix or a glob that no use case fits.
  static func selectorMatchesNothing(
    _ kind: String,
    _ selector: String,
    at place: String,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "selector-matches-nothing",
      in: file,
      message: "\(kind) \(AuthoredValue.quote(selector)) matches nothing at \(place)",
    )
  }

  /// A group that resolves to no use case.
  static func groupHasNoMembers(
    _ group: IdentifierSegment,
    in file: WorkspacePath,
  ) -> Diagnostic {
    Diagnostic(
      warning: "group-has-no-members",
      in: file,
      message: "group \(AuthoredValue.quote(group.text)) has no members",
    )
  }
}
