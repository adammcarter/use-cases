/// What the command line asks of `docs` (chapter 16 §16).
public enum DocsRequest: Equatable, Sendable {
  /// No words: the list of guides.
  case list

  /// A guide's name, which shows the guide, or words to look for in the guides. Nothing is
  /// checked yet: `pageSize` is text, so that a refusal is in this command's own words.
  case words(
    String,
    isExact: Bool,
    pageSize: String?,
  )

  /// The following page of an earlier search: its `--next` token, which carries everything else.
  case continuing(token: String)
}
