/// One scope's `use-cases.yml` (chapter 04), read and with its defaults filled in.
struct ScopeConfiguration: Equatable, Sendable {
  /// What an omitted `use_cases_dir` means.
  static let defaultUseCasesDirectoryText = "use-cases"

  let schemaVersion: Int

  /// Whether the file says `root: true`. Only the root scope's does.
  let declaresRoot: Bool

  /// The scope's own prefix. A scope without one passes its parent's namespace through.
  let prefix: Namespace?

  /// Where the scope's definition files are, relative to the scope's directory. It never
  /// escapes the scope.
  let useCasesDirectory: WorkspacePath

  /// The repository-wide settings; only the root scope has them.
  let rootSettings: RootSettings?
}
