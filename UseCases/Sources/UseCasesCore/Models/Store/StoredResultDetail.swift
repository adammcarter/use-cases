/// Everything a result of a supported record version holds beyond the envelope (chapter 12 §12
/// and §14).
struct StoredResultDetail: Equatable, Sendable {
  /// UTC RFC 3339, diagnostic only: no timestamp controls ordering.
  let recordedAt: String

  let origin: ResultOrigin
  let message: String?
  let attachments: [ResultAttachment]
}
