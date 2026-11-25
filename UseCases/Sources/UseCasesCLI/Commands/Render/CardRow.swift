/// One row of a card between its sides: some text, set as a header or not.
struct CardRow: Equatable {
  let text: String
  let isHeader: Bool

  static let blank = CardRow(text: "", isHeader: false)
}

extension CardRow {
  /// The row between the sides of a card `inner` scalars wide: two spaces, the text, and spaces
  /// to the edge. A header is set after the spaces are counted.
  func line(
    inner: Int,
    style: LayoutStyle,
  ) -> String {
    guard !text.isEmpty else {
      return "│" + String(repeating: " ", count: inner) + "│"
    }

    let shown = isHeader ? style.header(text) : text
    let padding = String(repeating: " ", count: max(0, inner - 2 - text.scalarCount))

    return "│  \(shown)\(padding)│"
  }
}
