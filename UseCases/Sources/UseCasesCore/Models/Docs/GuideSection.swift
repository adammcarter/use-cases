/// One part of a guide that stands alone, and is what a search of the guides finds.
public struct GuideSection: Equatable, Sendable {
  /// The `##` heading; for the lead paragraph, the guide's title.
  public let heading: String

  /// The text under the heading, without surrounding blank lines.
  public let body: String

  /// A section.
  public init(
    heading: String,
    body: String,
  ) {
    self.heading = heading
    self.body = body
  }
}
