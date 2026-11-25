import UseCasesCore

extension VerificationStatus {
  /// The symbol before the word (chapter 16 §19). A symbol is always followed by its word, so
  /// nothing depends on the symbol alone.
  var symbol: String {
    switch self {
    case .failed:
      "✗"
    case .error:
      "!"
    case .stale:
      "~"
    case .incomplete:
      "◐"
    case .unverified:
      "○"
    case .verified:
      "✓"
    case .draft:
      "·"
    }
  }

  /// The symbol and its word, as a list or a table shows the state.
  var marked: String {
    "\(symbol) \(rawValue)"
  }
}
