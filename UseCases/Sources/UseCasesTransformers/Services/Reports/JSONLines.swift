/// A report that holds one JSON value per line.
struct JSONLines {
  struct Line {
    /// 1-based line number in the report.
    let number: Int
    /// Nil when the line is not JSON.
    let value: JSONValue?
  }

  let lines: [Line]

  /// The non-blank lines of `text`, each read as JSON.
  init(text: String) {
    var found: [Line] = []

    for (index, raw) in text.reportLines.enumerated() {
      guard !raw.allSatisfy(\.isWhitespace) else {
        continue
      }

      found.append(
        Line(
          number: index + 1,
          value: JSONValue.parse(String(raw)),
        ),
      )
    }

    lines = found
  }
}
