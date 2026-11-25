/// Why `init` refused before writing anything (chapter 17 §3, §9).
public enum InitError: Error, Equatable, Sendable {
  /// `--prefix` is not a prefix (chapter 05).
  case invalidPrefix(
    text: String,
    reason: String,
  )

  /// The folder to set up is not a folder.
  case notAFolder(path: String)

  /// The folder holds a `use-cases.yml` that does not say `root: true`: a child scope.
  case notWorkspaceRoot(path: String)

  /// The folder is below a workspace root; a second root there would split the workspace.
  case insideWorkspace(
    folder: String,
    root: String,
  )

  /// `--prefix` differs from the prefix the workspace already has, which `init` never changes.
  case differentPrefix(
    existing: String?,
    asked: String,
  )

  /// The root `use-cases.yml` here or above cannot be used, so the workspace is INVALID. Each
  /// problem is one line.
  case invalidWorkspace(problems: [String])

  /// Something stands where a file or folder of the setup would go.
  case obstructed(
    path: String,
    reason: String,
  )

  /// The schemas that ship inside this build could not be loaded, so nothing could be checked.
  case unavailable(message: String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .invalidPrefix(text, reason):
      "'\(text)' is not a valid prefix: \(reason)"
    case let .notAFolder(path):
      "'\(path)' is not a folder"
    case let .notWorkspaceRoot(path):
      "'\(path)' is not a workspace root: its use-cases.yml does not say root: true, so it is "
        + "a child scope. Run init in the workspace root, or in a folder that has no use-cases.yml"
    case let .insideWorkspace(folder, root):
      "'\(folder)' is inside the workspace at '\(root)': a second root here would split the "
        + "workspace. Run init in '\(root)' or outside it"
    case let .differentPrefix(existing, asked):
      "--prefix '\(asked)' differs from the workspace, which \(Self.describing(existing)); "
        + "init never changes a prefix, because that renames every use case"
    case let .invalidWorkspace(problems):
      problems.joined(separator: "\n")
    case let .obstructed(path, reason):
      "\(path) cannot be used: \(reason)"
    case let .unavailable(message):
      message
    }
  }

  private static func describing(_ prefix: String?) -> String {
    guard let prefix else {
      return "has no prefix"
    }

    return "has the prefix '\(prefix)'"
  }
}
