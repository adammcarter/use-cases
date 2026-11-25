/// One guide that ships with the tool (chapter 16 §16): a page for one task, written for this
/// version.
public struct Guide: Equatable, Sendable {
  /// The name the guide is shown by: its file's name without `.md`.
  public let name: String

  /// The `#` heading on its first line.
  public let title: String

  /// What the guide covers: the first paragraph under the title.
  public let covers: String

  /// The whole page, exactly as written.
  public let text: String

  /// The lead paragraph under the title, then each `##` section; a search finds one at a time.
  public let sections: [GuideSection]

  /// A guide.
  public init(
    name: String,
    title: String,
    covers: String,
    text: String,
    sections: [GuideSection],
  ) {
    self.name = name
    self.title = title
    self.covers = covers
    self.text = text
    self.sections = sections
  }
}
