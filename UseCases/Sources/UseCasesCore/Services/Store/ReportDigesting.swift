/// Digests the files the tests wrote into a run's reports folder (chapter 12 §15, §20). It never
/// throws on what the tests wrote: an entry that is not a regular file, or cannot be read, is
/// reported beside the digests and is never followed.
protocol ReportDigesting: Sendable {
  /// The digest of every regular file below the folder, and the entries that cannot be digested.
  ///
  /// - Parameters:
  ///   - folder: `reports/`, or one validation's folder in it.
  ///   - prefix: Put before each path, so that the paths of one validation's folder are from
  ///     `reports/`: `unit-tests/` for `reports/unit-tests`.
  func digests(
    below folder: StoreFile,
    prefix: String,
  ) -> ReportDigests

  /// The entries below `reports/` that are not regular files, without reading any file.
  func unusableEntries(below folder: StoreFile) -> [UnusableReportEntry]
}
