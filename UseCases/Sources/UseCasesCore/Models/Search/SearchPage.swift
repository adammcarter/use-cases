/// One page of the use cases that match a search, best first (chapter 16 §15).
public struct SearchPage: Equatable, Sendable {
  /// How many use cases match, across every page.
  public let total: Int

  /// How many matches come before this page.
  public let offset: Int

  public let pageSize: Int

  public let matches: [SearchMatch]

  /// The token for the following page; `nil` on the last.
  public let next: String?

  /// A page.
  public init(
    total: Int,
    offset: Int,
    pageSize: Int,
    matches: [SearchMatch],
    next: String?,
  ) {
    self.total = total
    self.offset = offset
    self.pageSize = pageSize
    self.matches = matches
    self.next = next
  }
}
