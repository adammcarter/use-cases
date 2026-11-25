import UseCasesCore

extension BriefCard {
  /// How wide a card is, in Unicode scalars, unless its id needs more.
  static let width = 63

  /// What a card needs beyond its id: the corners, the dashes and a space on either side.
  private static let idMargin = 12

  /// The lines of the card: its id at the top right, and every row exactly as wide as the card.
  func lines(style: LayoutStyle) -> [String] {
    let width = max(Self.width, useCase.scalarCount + Self.idMargin)
    let inner = width - 2
    let top = "┌" + String(repeating: "─", count: width - 6 - useCase.scalarCount)
      + " \(useCase) ──┐"
    let bottom = "└" + String(repeating: "─", count: inner) + "┘"

    return [top] + rows(textWidth: inner - 4).map { row in
      row.line(
        inner: inner,
        style: style,
      )
    } + [bottom]
  }

  /// The rows of the card, whose text never goes past `textWidth` Unicode scalars.
  func rows(textWidth: Int) -> [CardRow] {
    var rows: [CardRow] = [
      .blank,
      CardRow(text: heading, isHeader: true),
    ]

    rows += title.wrapped(toScalars: textWidth).map { line in
      CardRow(text: line, isHeader: false)
    }
    rows += section(
      "NOW",
      [("", now)],
      textWidth: textWidth,
    )

    if let was {
      rows += section(
        "WAS",
        [("", was)],
        textWidth: textWidth,
      )
    }

    rows += section(
      "SCENARIOS",
      scenarios.map { scenario in
        (scenario.isGolden ? "✓ golden   " : "◇ edge     ", scenario.text)
      },
      textWidth: textWidth,
    )
    rows += section(
      "NOT INCLUDED",
      notIncluded.map { item in
        ("✗ ", item)
      },
      textWidth: textWidth,
    )
    rows += section(
      "PROVEN BY",
      provenBy.isEmpty ? [] : [("", provenBy.joined(separator: " · "))],
      textWidth: textWidth,
    )

    return rows + [.blank]
  }

  private var heading: String {
    guard let tier else {
      return fit.rawValue.uppercased()
    }

    return "\(fit.rawValue.uppercased()) · \(tier)"
  }

  /// A blank row, the header, and each item with its marker, the rest of an item set under its
  /// own words. A section with no items is left out.
  private func section(
    _ header: String,
    _ items: [(marker: String, text: String)],
    textWidth: Int,
  ) -> [CardRow] {
    guard !items.isEmpty else {
      return []
    }

    var rows = [
      CardRow.blank,
      CardRow(text: header, isHeader: true),
    ]

    for item in items {
      let indent = 2 + item.marker.scalarCount
      let lines = item.text.wrapped(toScalars: textWidth - indent)

      for (number, line) in lines.enumerated() {
        let marker = number == 0 ? item.marker : String(
          repeating: " ",
          count: item.marker.scalarCount,
        )

        rows.append(CardRow(text: "  \(marker)\(line)", isHeader: false))
      }
    }

    return rows
  }
}
