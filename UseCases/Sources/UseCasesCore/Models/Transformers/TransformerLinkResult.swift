/// What a results transformer reported for one validation link (chapter 10 §13).
struct TransformerLinkResult: Equatable, Sendable {
  /// The core-assigned key of the link, as the request gave it.
  let link: String

  /// The worst verdict of every test that fell inside the link.
  let status: Verdict

  /// The opaque IDs of those tests, in the order reported, without repeats.
  let tests: [String]

  /// A short note for people; it never changes the status.
  let message: String?
}
