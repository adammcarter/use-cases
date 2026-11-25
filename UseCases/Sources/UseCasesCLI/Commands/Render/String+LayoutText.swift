extension String {
  /// How many Unicode scalars the text has: the width of a layout is counted in them, never in
  /// what a terminal shows.
  var scalarCount: Int {
    unicodeScalars.count
  }

  /// The words of the text, each run of white space of any kind, a line break included, one
  /// space, and none at either end, and every character a terminal would act on spelled out
  /// (`\x1B`, `\u202E`): a layout shows text, it never lets text move the cursor.
  var collapsingWhitespace: String {
    unicodeScalars.split { scalar in
      scalar.properties.isWhitespace
    }.map { word in
      String(word).displayEscaped
    }.joined(separator: " ")
  }

  /// The text followed by spaces, to at least `width` Unicode scalars.
  func padded(toScalars width: Int) -> String {
    self + String(
      repeating: " ",
      count: max(0, width - scalarCount),
    )
  }

  /// The text without the spaces at its end.
  var withoutTrailingSpaces: String {
    var text = self

    while text.hasSuffix(" ") {
      text.removeLast()
    }

    return text
  }

  /// The text in lines of at most `width` Unicode scalars, broken at spaces only. A word longer
  /// than a line is broken where the line ends. The text has no lines of its own: white space
  /// of any kind is one space. Text with no words is one empty line.
  func wrapped(toScalars limit: Int) -> [String] {
    let width = max(1, limit)
    var lines: [String] = []
    var line = ""

    for word in collapsingWhitespace.split(separator: " ") {
      var rest = String(word)

      if !line.isEmpty, line.scalarCount + 1 + rest.scalarCount <= width {
        line += " " + rest
        continue
      }

      if !line.isEmpty {
        lines.append(line)
        line = ""
      }

      while rest.scalarCount > width {
        lines.append(String(rest.unicodeScalars.prefix(width)))
        rest = String(rest.unicodeScalars.dropFirst(width))
      }

      line = rest
    }

    return line.isEmpty ? (lines.isEmpty ? [""] : lines) : lines + [line]
  }
}
