/// One piece of text of a use case that a search looks in, and where it is.
struct UseCasePassage: Equatable, Sendable {
  let field: SearchField

  /// The scenario or route the text is in.
  let location: String?

  let passage: SearchPassage
}
