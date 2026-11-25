import UseCasesCore

extension ProposalLayout {
  /// The title, a line for each use case, the choices, who signs, and the ids last (chapter 21 §7).
  func text(style: LayoutStyle) -> String {
    var lines = [
      style.header("PROPOSAL · \(title.collapsingWhitespace)"),
      "",
    ]
    let width = changes.map(\.title.collapsingWhitespace.scalarCount).max() ?? 0

    lines += changes.map { change in
      change.line(
        titleWidth: width,
        style: style,
      )
    }
    lines.append("")

    lines += decisions.map { decision in
      let options = decision.options.enumerated().map { number, option in
        "\(number + 1)) \(option.collapsingWhitespace)"
      }.joined(separator: "   ")

      let question = decision.question.collapsingWhitespace

      return "  \(style.header("YOUR CALL"))    \(question):  \(options)"
    }

    if let signing = signOff.words {
      lines.append("  \(style.header("SIGN-OFF"))     \(signing)")
    }

    lines.append(
      "  \(style.header("ids"))          "
        + changes.map(\.useCase).joined(separator: " · "),
    )

    return lines.joined(separator: "\n")
  }
}

private extension ProposalChange {
  /// The symbol, the fit, the title, and what the person will see, or that it was checked.
  func line(
    titleWidth: Int,
    style: LayoutStyle,
  ) -> String {
    let words = title.collapsingWhitespace.padded(toScalars: titleWidth)
    let tail = if let youSee {
      "   you'll see: \(youSee.collapsingWhitespace)"
    } else if fit == .untouched {
      "   (checked, stays as it is)"
    } else {
      ""
    }

    let label = style.header(fit.rawValue.uppercased().padded(toScalars: 9))

    return "  \(fit.symbol) \(label)  \(words)\(tail)".withoutTrailingSpaces
  }
}
