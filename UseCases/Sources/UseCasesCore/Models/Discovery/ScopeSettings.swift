/// What discovery needs from one scope's `use-cases.yml`.
///
/// Reading the file (parsing, schema, defaults) belongs to a `ScopeSettingsReading`; discovery
/// only acts on these three answers.
struct ScopeSettings: Equatable, Sendable {
  /// Whether the file says `root: true`.
  let isRoot: Bool

  /// The scope's `use_cases_dir`, relative to the scope's folder, with its default already
  /// applied. `.` is the scope's own folder.
  let useCasesDirectory: WorkspacePath

  /// The `discovery.exclude` patterns. Only the root's are used: the setting is root-only.
  let excludes: [PathPattern]
}
