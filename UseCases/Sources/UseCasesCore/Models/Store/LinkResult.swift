/// What one validation link of a route received (chapter 12 §12): a verdict, or none when no
/// test reported for it.
struct LinkResult: Equatable, Sendable {
  /// The core-assigned key: `<use case>#[<route>.]<binding>@<file>:<start line>`.
  let key: String

  /// `nil` when the link received no result, which can only be when another link failed.
  let verdict: Verdict?
}
