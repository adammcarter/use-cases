import UseCasesCore

extension UseCaseStatus {
  /// The reason beside the use case in a list (chapter 16 §9): what a DRAFT lacks, or the gating
  /// route that decided the state and why. Nothing for a use case that is verified, and then
  /// `changed since approved` when the promise changed after its sign-off.
  func listingReason(shortRunIdentifiers: Bool) -> String? {
    var reasons: [String] = []

    if !isReady {
      reasons.append("missing: \(missing.joined(separator: ", "))")
    } else if status != .verified, let route = decidingRoute {
      reasons.append(route.listing(shortRunIdentifiers: shortRunIdentifiers))
    }

    if approval == .changed {
      reasons.append("changed since approved")
    }

    return reasons.isEmpty ? nil : reasons.joined(separator: " · ")
  }
}

extension RouteStatus {
  /// `unit-tests failed (run 0192f0c4 via unit-tests)` where a result decided it, and
  /// `unit-tests: changed since run 0191aa02` where none did.
  func listing(shortRunIdentifiers: Bool) -> String {
    let why = explanation.text(shortRunIdentifiers: shortRunIdentifiers)

    guard case .decided = explanation else {
      return "\(identifier): \(why)"
    }

    return "\(identifier) \(status.rawValue) (\(why))"
  }
}
