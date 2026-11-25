/// One entry of `validations:` in the bridge settings (chapter 10 §7).
struct BridgeValidation: Equatable, Sendable {
  let identifier: IdentifierSegment

  /// The report's file or folder name inside the run's reports folder.
  let report: String?

  /// The argument vector `verify --run` starts.
  let run: [String]?

  /// The folder the command runs in, relative to the workspace root; `nil` for the root.
  let workingDirectory: WorkspacePath?

  let transformer: TransformerReference

  /// Passed to the transformer unchanged; `nil` when the entry has none.
  let settings: AuthoredValue?
  let timeoutSeconds: Int?
}
