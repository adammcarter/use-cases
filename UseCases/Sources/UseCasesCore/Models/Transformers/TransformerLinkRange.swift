/// The lines a link names, as the transformer wrote them: a member that was not there is `nil`.
struct TransformerLinkRange: Equatable, Sendable {
  let start: Int?
  let end: Int?
}
