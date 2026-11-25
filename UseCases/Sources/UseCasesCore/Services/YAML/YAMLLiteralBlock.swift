/// Multi-line text written as a literal block (`|`), the way people write it by hand.
struct YAMLLiteralBlock: Equatable, Sendable {
  /// What follows the key or the dash: `|`, with an indentation digit when the first line starts
  /// with a space or a tab, and a chomping indicator (`-` strips the last line break, `+` keeps all
  /// the
  /// trailing ones, nothing keeps one).
  let header: String

  /// The lines under the header, already indented. A blank line is empty.
  let lines: [String]
}
