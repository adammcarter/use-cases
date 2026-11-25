import Foundation

/// What one discovery run shares between its steps.
struct DiscoveryContext {
  /// The canonical folder of the workspace root.
  let rootDirectory: URL

  /// The default exclusions: the tool's own store and version-control history.
  let builtInExcludes: [PathPattern]

  /// The root's `discovery.exclude`.
  let configuredExcludes: [PathPattern]

  /// Folders that hold a `use-cases.yml`, and nested workspaces: a definition walk never enters
  /// one, because a folder owned by another scope's configuration owns its own files.
  var claimedDirectories: Set<WorkspacePath> = []

  /// Where a workspace path is on disk.
  func url(for path: WorkspacePath) -> URL {
    guard !path.isRoot else {
      return rootDirectory
    }

    return rootDirectory.appendingPathComponent(path.text)
  }

  /// Whether discovery must not enter this path, or look at it: a pattern matches it or a
  /// folder above it (chapter 04, "Discovery exclusions").
  func isExcluded(_ path: WorkspacePath) -> Bool {
    exclusion(covering: path) != nil
  }

  /// The first pattern that covers the path, the built-in ones first.
  func exclusion(covering path: WorkspacePath) -> ExclusionMatch? {
    if let pattern = builtInExcludes.first(where: { pattern in
      pattern.excludes(path)
    }) {
      return ExclusionMatch(
        pattern: pattern.text,
        isBuiltIn: true,
      )
    }

    guard
      let pattern = configuredExcludes.first(where: { pattern in
        pattern.excludes(path)
      })
    else {
      return nil
    }

    return ExclusionMatch(
      pattern: pattern.text,
      isBuiltIn: false,
    )
  }
}
