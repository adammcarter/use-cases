/// Where a scalar is written, which decides what may stay unquoted.
enum YAMLScalarContext: Sendable {
  /// A value or a key on a line of its own, or after a `- `.
  case block

  /// An item of a list or mapping written on one line, where `,`, `[`, `]`, `{`, `}` and `:`
  /// would be read as structure.
  case flow
}
