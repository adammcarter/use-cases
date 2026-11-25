/// One region a binding contributes: where it is and what it holds. Content mode uses only the
/// content, content-and-locator mode both (chapter 11 §89.5).
struct LinkRegionContribution: Equatable, Sendable {
  let locator: FingerprintLocator
  let content: ContentReference

  /// Sorts by locator, then by content (§89.5, content-and-locator mode).
  func precedesByLocator(_ other: LinkRegionContribution) -> Bool {
    if locator != other.locator {
      return locator.precedes(other.locator)
    }

    return content.precedes(other.content)
  }
}
