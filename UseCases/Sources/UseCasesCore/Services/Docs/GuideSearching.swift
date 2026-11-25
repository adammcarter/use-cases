/// Finds the sections of the guides that match a search, ranked as `search` ranks use cases
/// (chapter 16 §16).
public protocol GuideSearching: Sendable {
  /// One page of the sections that match, best first.
  ///
  /// - Parameters:
  ///   - plan: What to look for and which page.
  ///   - guides: Every guide, in the order of the design.
  /// - Throws: ``GuideSearchError`` when a page after the first is asked for and the guides are
  ///   not as they were.
  func search(
    _ plan: GuidePlan,
    in guides: [Guide],
  ) throws(GuideSearchError) -> GuidePage
}
