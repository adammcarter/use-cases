/// Measures how deeply a file nests its lists and mappings without composing it, because
/// composing a very deep file overflows the stack.
protocol YAMLNestingScanning: Sendable {
  /// The first line on which the text is nested deeper than `limit` levels, if there is one.
  func firstLine(
    deeperThan limit: Int,
    in source: YAMLSourceText,
  ) -> Int?
}
