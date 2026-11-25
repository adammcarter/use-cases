extension String {
  /// The lines of a text, split at line feeds only, so line numbers agree with the core's count.
  /// A carriage return stays at the end of its line.
  var sourceLines: [String] {
    var lines: [String] = []
    var current = String.UnicodeScalarView()

    for scalar in unicodeScalars {
      if scalar == "\n" {
        lines.append(String(current))
        current = String.UnicodeScalarView()
      } else {
        current.append(scalar)
      }
    }

    lines.append(String(current))

    return lines
  }

  /// The lines of a tool's report: split at line feeds only, with one carriage return dropped
  /// from the end of each line. A report holds JSON and console text, and U+2028, U+0085 and a
  /// lone carriage return are legal inside a JSON string, so none of them ends a line.
  var reportLines: [String] {
    sourceLines.map { line in
      line.unicodeScalars.last == "\r" ? String(line.unicodeScalars.dropLast()) : line
    }
  }
}
