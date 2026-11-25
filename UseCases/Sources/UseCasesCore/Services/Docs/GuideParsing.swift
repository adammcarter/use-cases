/// Reads the text of a guide page (chapter 16 §16): a title, a first paragraph saying what it
/// covers, then short `##` sections that each stand alone.
protocol GuideParsing: Sendable {
  /// The guide a page of text is.
  ///
  /// - Throws: ``GuideParsingError`` for a page with no title, or none under it to say what it
  ///   covers.
  func guide(
    named name: String,
    text: String,
  ) throws(GuideParsingError) -> Guide
}
