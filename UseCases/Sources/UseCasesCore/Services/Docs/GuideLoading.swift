/// Reads the guides that ship with the tool (chapter 16 §16).
public protocol GuideLoading: Sendable {
  /// Every guide, in the order of the design.
  ///
  /// - Throws: ``GuideLoadingError`` for a guide the build does not hold, or one that is not a
  ///   guide.
  func guides() throws(GuideLoadingError) -> [Guide]
}
