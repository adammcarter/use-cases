/// One page of the sections that match a search of the guides, best first (chapter 16 §16).
public struct GuidePage: Equatable, Sendable {
  /// How many sections match, across every page.
  public let total: Int

  /// How many matches come before this page.
  public let offset: Int

  public let pageSize: Int

  public let matches: [GuideMatch]

  /// The token for the following page; `nil` on the last.
  public let next: String?

  /// A page.
  public init(
    total: Int,
    offset: Int,
    pageSize: Int,
    matches: [GuideMatch],
    next: String?,
  ) {
    self.total = total
    self.offset = offset
    self.pageSize = pageSize
    self.matches = matches
    self.next = next
  }
}
