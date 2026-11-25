/// Writes a value as authored YAML, the way a person lays it out.
protocol YAMLEmitting: Sendable {
  /// The lines of the value, starting at the left edge, without line breaks. A mapping or a
  /// list is written in block form, lists indented under their key; a list or mapping of text,
  /// numbers and booleans alone goes on one line when the whole line fits the layout, and is a
  /// block otherwise. A list item that is a mapping is always a block.
  func lines(of value: StoreJSONValue) -> [String]
}
