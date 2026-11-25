import UseCasesCore

extension BriefLayout {
  /// The cards one after the other, a blank line between (chapter 21 §7).
  func text(style: LayoutStyle) -> String {
    cards.map { card in
      card.lines(style: style).joined(separator: "\n")
    }.joined(separator: "\n\n")
  }
}
