/// A file under a run folder and the SHA-256 digest of its exact bytes.
struct FileDigest: Equatable, Sendable {
  /// The path relative to the folder the digest map belongs to (`outputs/` or `reports/`).
  let path: String

  /// 64 lowercase hex digits.
  let digest: String
}
