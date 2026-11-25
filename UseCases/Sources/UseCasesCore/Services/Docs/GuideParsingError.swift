/// Why the text of a guide is not a guide.
enum GuideParsingError: Error, Equatable, Sendable {
  /// The first line is not a `# ` heading with a title.
  case noTitle

  /// There is no paragraph under the title to say what the guide covers.
  case noLead
}
