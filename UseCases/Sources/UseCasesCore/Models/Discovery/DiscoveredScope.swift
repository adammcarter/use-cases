/// One scope found below the workspace root, with the definition files it owns.
struct DiscoveredScope: Equatable, Sendable {
  /// The scope's folder, `.` for the root scope.
  let directory: WorkspacePath

  /// The scope above this one: the nearest ancestor folder holding a `use-cases.yml`. The root
  /// scope has none.
  let parent: WorkspacePath?

  /// The scope's `use_cases_dir` in workspace coordinates.
  let useCasesDirectory: WorkspacePath

  /// Every `.yml` and `.yaml` file the scope owns, below its `use_cases_dir`, sorted by path.
  let definitionFiles: [WorkspacePath]

  /// The scope's own `use-cases.yml`.
  var configuration: WorkspacePath {
    directory.appending(literal: Self.configurationFileName)
  }

  var isRoot: Bool {
    directory.isRoot
  }

  /// The one name a scope's configuration file has.
  static let configurationFileName = "use-cases.yml"
}
