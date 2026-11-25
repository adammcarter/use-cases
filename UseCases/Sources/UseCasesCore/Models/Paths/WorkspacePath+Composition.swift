extension WorkspacePath {
  /// The workspace root itself, written `.`.
  static let root = WorkspacePath(spelledCanonically: ".")

  /// The last segment: a file or folder name. The workspace root has none.
  var name: String? {
    isRoot ? nil : segments.last
  }

  /// The folder this path sits in. The workspace root has none.
  var parent: WorkspacePath? {
    guard !isRoot else {
      return nil
    }

    let parentSegments = segments.dropLast()

    guard !parentSegments.isEmpty else {
      return .root
    }

    return WorkspacePath(spelledCanonically: parentSegments.joined(separator: "/"))
  }

  /// This path with one more name below it, such as a file or folder found on disk. A name that
  /// no path can spell (`..`, a control character, a backslash) is refused.
  func appending(component name: String) throws(WorkspacePathError) -> WorkspacePath {
    try WorkspacePath(validating: isRoot ? name : "\(text)/\(name)")
  }

  /// This path with one more name found in a folder listing. A name that is not valid UTF-8 is
  /// refused: no path can spell it.
  func appending(entry: FileEntry) throws(WorkspacePathError) -> WorkspacePath {
    guard entry.isNameUTF8 else {
      throw .notUTF8(entry.name)
    }

    return try appending(component: entry.name)
  }

  /// This path with one more name that the code itself writes, such as `use-cases.yml`. It is
  /// for names known to be one valid segment; a name read from disk goes through
  /// `appending(component:)`.
  func appending(literal name: String) -> WorkspacePath {
    WorkspacePath(spelledCanonically: isRoot ? name : "\(text)/\(name)")
  }

  /// This path followed by a path that is relative to it, such as a scope's `use_cases_dir`
  /// below the scope's folder. `.` adds nothing.
  func joining(_ relative: WorkspacePath) -> WorkspacePath {
    if relative.isRoot {
      return self
    }

    if isRoot {
      return relative
    }

    return WorkspacePath(spelledCanonically: "\(text)/\(relative.text)")
  }

  /// Whether this path is `ancestor` or lies below it, compared segment by segment and byte for
  /// byte: `a/b` is inside `a`, `ab` is not, and the workspace root holds everything.
  func isInsideOrEqual(to ancestor: WorkspacePath) -> Bool {
    if ancestor.isRoot {
      return true
    }

    if isRoot {
      return false
    }

    let mine = segments
    let theirs = ancestor.segments

    guard mine.count >= theirs.count else {
      return false
    }

    return zip(mine, theirs).allSatisfy { mine, theirs in
      mine.isExactlyEqual(to: theirs)
    }
  }

  /// Every folder from this path's parent up to the workspace root, nearest first.
  var ancestors: [WorkspacePath] {
    var result: [WorkspacePath] = []
    var current = parent

    while let folder = current {
      result.append(folder)
      current = folder.parent
    }

    return result
  }

  /// For text that is a valid path by construction, such as two valid paths joined with `/`.
  private init(spelledCanonically text: String) {
    self.text = text
  }
}
