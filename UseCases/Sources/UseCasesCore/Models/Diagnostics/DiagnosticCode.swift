/// A short, stable name for a kind of problem, such as `invalid-id`. Diagnostics with one
/// position sort by it (chapter 09 §27.1), compared by UTF-8 bytes.
struct DiagnosticCode: Hashable, Comparable, Sendable, ExpressibleByStringLiteral,
  CustomStringConvertible
{
  let text: String

  init(_ text: String) {
    self.text = text
  }

  init(stringLiteral value: String) {
    text = value
  }

  var description: String {
    text
  }

  static func == (
    lhs: DiagnosticCode,
    rhs: DiagnosticCode,
  ) -> Bool {
    lhs.text.isExactlyEqual(to: rhs.text)
  }

  static func < (
    lhs: DiagnosticCode,
    rhs: DiagnosticCode,
  ) -> Bool {
    lhs.text.precedesExactly(rhs.text)
  }

  func hash(into hasher: inout Hasher) {
    text.hashExactly(into: &hasher)
  }
}
