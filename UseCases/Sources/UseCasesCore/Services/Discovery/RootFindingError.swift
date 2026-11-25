import Foundation

/// Why no workspace root could be named.
enum RootFindingError: Error, Equatable, Sendable {
  /// No folder from the start up to the top of the file system holds a `use-cases.yml` that
  /// says `root: true`.
  case noRootFound(startingAt: URL)

  /// The folder's `use-cases.yml` does not say `root: true`: it is a child scope, and its IDs
  /// would come out different from the workspace's.
  case notTheRoot(URL)

  /// The folder has no `use-cases.yml` at all.
  case noConfiguration(URL)

  /// The folder's `use-cases.yml` is a symlink, which is never followed or read.
  case configurationIsSymlink(URL)

  /// A `use-cases.yml` that decides the answer could not be read.
  case unreadableConfiguration(folder: URL, reason: ScopeSettingsLoadingError)
}

extension RootFindingError: CustomStringConvertible {
  var description: String {
    switch self {
    case .noRootFound:
      "no use-cases.yml with root: true in this folder or any folder above it; "
        + "run `use-cases init`"
    case let .notTheRoot(folder):
      "'\(folder.path)' is a child scope: its use-cases.yml does not say root: true, so its "
        + "IDs would come out different from the workspace's; name the workspace root, the "
        + "folder whose use-cases.yml says root: true"
    case let .noConfiguration(folder):
      "'\(folder.path)' has no use-cases.yml; the workspace root is the folder whose "
        + "use-cases.yml says root: true"
    case let .configurationIsSymlink(folder):
      "'\(folder.appendingPathComponent(DiscoveredScope.configurationFileName).path)' is a "
        + "symlink; a use-cases.yml must be the file itself, because a symlink is never "
        + "followed or read"
    case let .unreadableConfiguration(folder, reason):
      "'\(folder.appendingPathComponent(DiscoveredScope.configurationFileName).path)' "
        + "cannot be used to find the workspace root: \(reason.summary)"
    }
  }
}
