/// Where a link was found (chapter 08 "Two ways to link").
public enum LinkSource: String, Sendable {
  /// A `@use-case:` comment pair in the code.
  case marker

  /// A manual binding written in a use case's YAML.
  case manual

  /// A link a links transformer of the bridge settings returned (chapter 10 §11).
  case transformer
}
