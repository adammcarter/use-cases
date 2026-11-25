/// What digesting the files under a reports folder found.
struct ReportDigests: Equatable, Sendable {
  /// The SHA-256 of every regular file, by path, sorted by the bytes of the path.
  let digests: [FileDigest]

  /// Everything that could not be digested, sorted by path.
  let unusable: [UnusableReportEntry]
}
