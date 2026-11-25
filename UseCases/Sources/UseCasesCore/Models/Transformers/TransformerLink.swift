/// A link as a links transformer reported it, before the core has checked it (chapter 10 §11).
/// Every member is optional because the core trusts nothing: a member that is not there is a
/// problem with the link, found when the link is checked.
struct TransformerLink: Equatable, Sendable {
  let useCase: String?
  let route: String?
  let binding: String?
  let role: String?
  let file: String?

  /// `nil` for a link that covers a whole file.
  let range: TransformerLinkRange?

  /// The link as it came, printed on one line, for a message.
  let text: String
}
