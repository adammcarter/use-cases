/// How the headers of a layout are set: bold in a terminal, plain capitals everywhere else
/// (chapter 21 §7).
struct LayoutStyle: Equatable {
  /// Headers as they are, for a pipe, a chat and a `--json` document.
  static let plain = LayoutStyle(isBold: false)

  /// Headers in bold, for a terminal.
  static let bold = LayoutStyle(isBold: true)

  let isBold: Bool

  /// The text as a header of this style. Padding is added before this, never after, so what is
  /// counted is what is seen.
  func header(_ text: String) -> String {
    isBold ? "\u{1B}[1m\(text)\u{1B}[0m" : text
  }
}
