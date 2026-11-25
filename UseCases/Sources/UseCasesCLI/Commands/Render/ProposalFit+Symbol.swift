import UseCasesCore

extension ProposalFit {
  /// The symbol before the fit (chapter 21 §7).
  var symbol: String {
    switch self {
    case .new:
      "+"
    case .extends, .changes:
      "~"
    case .replaces:
      "−"
    case .untouched:
      "="
    }
  }
}
