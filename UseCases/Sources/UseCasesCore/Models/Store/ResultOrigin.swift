/// Where a stored verdict came from (chapter 12 §12).
enum ResultOrigin: Equatable, Sendable {
  /// A verdict a person or agent supplied with `use-cases record`. It has no links.
  case recorded

  /// The reports of these validations, with what each validation link of the route received, in
  /// the order written.
  case validations(
    _ identifiers: [IdentifierSegment],
    links: [LinkResult],
  )
}
