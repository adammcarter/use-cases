/// What `use-cases verify --finish` did (chapter 13 §7): the sealed run, its manifest and its
/// results, or the note that there was nothing to read.
public struct VerifiedRun: Equatable, Sendable {
  /// The sealed run's manifest; `nil` when no run was read.
  let manifest: RunManifest?

  /// The verdicts the run sealed.
  let results: [StoredResult]

  /// The notes of a request that read nothing; a run's own notes are in its manifest.
  private let unreadNotes: [String]

  /// The request was cancelled and the run was sealed as interrupted (chapter 13 §15).
  public let isCancelled: Bool

  /// The sealed run's id; `nil` when no run was read.
  public var runIdentifier: String? {
    manifest?.identifier.text
  }

  /// The run-level problems, each starting with the id of the validation it is about.
  public var errors: [String] {
    manifest?.errors ?? []
  }

  /// Whether the run was sealed with run errors, which is what makes the request exit 1
  /// (chapter 16 §6).
  public var hasRunErrors: Bool {
    !errors.isEmpty
  }

  /// Guidance for the person.
  public var notes: [String] {
    manifest?.notes ?? unreadNotes
  }

  /// How many verdicts the run sealed of each status, for the statuses that have any, from `pass`
  /// to `error`.
  public var verdictCounts: [(status: String, count: Int)] {
    Verdict.allCases.compactMap { verdict in
      let count = results.filter { $0.verdict == verdict }.count

      return count == 0 ? nil : (status: verdict.rawValue, count: count)
    }
  }

  /// How many verdicts the run sealed.
  public var verdictCount: Int {
    results.count
  }

  init(
    manifest: RunManifest,
    results: [StoredResult],
    isCancelled: Bool,
  ) {
    self.manifest = manifest
    self.results = results
    self.isCancelled = isCancelled
    unreadNotes = []
  }

  /// A request with no validations to read: no run is written (chapter 13 §13).
  init(nothingToReadNotes notes: [String]) {
    manifest = nil
    results = []
    isCancelled = false
    unreadNotes = notes
  }
}
