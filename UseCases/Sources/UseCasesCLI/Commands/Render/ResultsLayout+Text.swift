import UseCasesCore

extension ResultsLayout {
  /// The title, a line for each use case and each removed one, the gate, and the ids last
  /// (chapter 21 §7).
  func text(style: LayoutStyle) -> String {
    let titles = useCases.map(\.title.collapsingWhitespace.scalarCount)
    let width = max(10, (titles + removed.map(\.scalarCount)).max() ?? 0)
    var lines = [
      style.header("RESULTS · \(title.collapsingWhitespace)"),
      "",
    ]

    lines += useCases.map { useCase in
      useCase.line(titleWidth: width)
    }
    lines += removed.map { identifier in
      "  − \(identifier.padded(toScalars: width))   removed"
    }
    lines.append("  \(style.header("gate"))   \(gatePasses ? "passes" : "blocked")")
    lines.append(
      "  \(style.header("ids"))    "
        + (useCases.map(\.useCase) + removed).joined(separator: " · "),
    )

    return lines.joined(separator: "\n")
  }
}

private extension ResultUseCase {
  func line(titleWidth: Int) -> String {
    let checks = checks.map { check in
      "\(check.label) \(check.status.symbol)"
    }.joined(separator: " · ")
    let words = title.collapsingWhitespace.padded(toScalars: titleWidth)

    return "  \(status.symbol) \(words)   \(checks)".withoutTrailingSpaces
  }
}
