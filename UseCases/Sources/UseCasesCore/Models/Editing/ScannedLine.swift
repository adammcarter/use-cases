/// One line of a definition file, read for what it is made of.
struct ScannedLine: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case blank

    /// A comment on a line of its own.
    case comment

    /// Anything else: a key, a dash, text, a line of a literal block.
    case content
  }

  let kind: Kind

  /// How many spaces the line starts with.
  let indent: Int

  /// What a content line says before its comment, as written. Empty for any other line.
  let code: String

  /// The comment that ends a content line, from its `#`.
  let trailingComment: String?

  /// Whether the line is text of a literal or folded block, which no comment can be in.
  let isBlockText: Bool

  /// Whether a block that keeps its trailing blank lines (`|+`) is open after this line, so that
  /// blank lines that follow are part of its text and not a gap.
  let keepsBlankLines: Bool

  static func blank(
    indent: Int,
    keepsBlankLines: Bool,
  ) -> ScannedLine {
    ScannedLine(
      kind: .blank,
      indent: indent,
      code: "",
      trailingComment: nil,
      isBlockText: false,
      keepsBlankLines: keepsBlankLines,
    )
  }

  static func comment(indent: Int) -> ScannedLine {
    ScannedLine(
      kind: .comment,
      indent: indent,
      code: "",
      trailingComment: nil,
      isBlockText: false,
      keepsBlankLines: false,
    )
  }

  static func blockText(
    indent: Int,
    keepsBlankLines: Bool,
  ) -> ScannedLine {
    ScannedLine(
      kind: .content,
      indent: indent,
      code: "",
      trailingComment: nil,
      isBlockText: true,
      keepsBlankLines: keepsBlankLines,
    )
  }
}
