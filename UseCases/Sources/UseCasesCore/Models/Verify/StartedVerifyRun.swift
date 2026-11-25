/// What `use-cases verify --start` did (chapter 13 §5): the run it opened and where the tests
/// write their reports, or the note that there was nothing to start.
public struct StartedVerifyRun: Equatable, Sendable {
  /// The run's id; `nil` when nothing was started.
  public let runIdentifier: String?

  /// Whether a run was opened.
  public var isStarted: Bool {
    runIdentifier != nil
  }

  /// The validations the run reads, in the order of the bridge settings.
  public let selected: [String]

  /// Where each selected validation's report goes.
  public let reports: [StartedReport]

  /// Guidance for the person: what to do next, and the other runs that are still open.
  public let notes: [String]

  /// Makes a description of a started run.
  public init(
    runIdentifier: String?,
    selected: [String],
    reports: [StartedReport],
    notes: [String],
  ) {
    self.runIdentifier = runIdentifier
    self.selected = selected
    self.reports = reports
    self.notes = notes
  }
}
