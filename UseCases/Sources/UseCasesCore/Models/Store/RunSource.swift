/// One bridge validation that fed a run (chapter 12 §11).
struct RunSource: Equatable, Sendable {
  let identifier: IdentifierSegment

  /// Where its report was written, relative to the run folder: `reports/<id>` or
  /// `reports/<id>/<name>`.
  let report: String

  /// The transformer's name or path.
  let transformer: String

  /// The folder its command ran in, when not the project root.
  let workingDirectory: WorkspacePath?

  /// The run command, present only when `verify --run` ran it.
  let command: [String]?
  let exitCode: Int?
  let seconds: Double?

  /// Why this source produced no results.
  let error: String?

  /// What the transformer said about the report, for people.
  let diagnostics: [String]
}
