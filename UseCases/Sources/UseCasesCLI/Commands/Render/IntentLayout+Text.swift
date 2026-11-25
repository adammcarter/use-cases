import UseCasesCore

extension IntentLayout {
  /// WHAT, WHY and, when it is said, WHO (chapter 21 §7).
  func text(style: LayoutStyle) -> String {
    var lines = [
      "\(style.header("WHAT"))   \(what.collapsingWhitespace)",
      "\(style.header("WHY"))    \(why.collapsingWhitespace)",
    ]

    if !who.isEmpty {
      lines.append(
        "\(style.header("WHO"))    "
          + who.map(\.collapsingWhitespace).joined(separator: " · "),
      )
    }

    return lines.joined(separator: "\n")
  }
}
