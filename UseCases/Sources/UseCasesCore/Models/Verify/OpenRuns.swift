/// Every unsealed run of a store: the ones that can be read, and the ones whose files are
/// damaged.
struct OpenRuns: Equatable, Sendable {
  /// In ascending run id.
  let open: [OpenVerifyRun]

  /// In ascending run id.
  let damaged: [DamagedRun]

  /// The record runs that are not sealed, in ascending run id. They are not verify runs: only
  /// `--abort` takes them.
  let records: [RunIdentifier]
}
