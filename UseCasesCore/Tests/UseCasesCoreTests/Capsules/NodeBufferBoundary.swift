import Testing

/// One shell script run past (or exactly at) node's `maxBuffer`, with the
/// bytes node kept for it.
struct NodeBufferBoundary: CustomTestStringConvertible, Sendable {
  /// sha256 of no bytes at all.
  static let emptyDigest =
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  /// One MiB plus the 64 KiB read that crossed it: what node keeps of a
  /// 1,200,000-byte stream.
  static let crossingDigest =
    "sha256:8fe763fc5836e60d96b1a56f5c4608bbf979701e8e2e845ffae4b6070273f132"

  let script: String
  let standardOutputBytes: Int
  let standardOutputDigest: String
  let standardErrorBytes: Int
  let standardErrorDigest: String
  let exitStatus: Int?
  let signal: String?

  var testDescription: String {
    "\(script) -> out \(standardOutputBytes) err \(standardErrorBytes)"
  }
}
