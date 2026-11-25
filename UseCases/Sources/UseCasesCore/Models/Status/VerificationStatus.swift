/// The state a use case or a route is listed in (chapter 07, chapter 16 §9). The cases are in the
/// order `status` lists them, worst first, and drafts after every verification state.
public enum VerificationStatus: String, CaseIterable, Sendable {
  /// Validation completed and the behaviour was not satisfied.
  case failed

  /// The validation mechanism failed, so the behaviour could not be determined.
  case error

  /// Validation did not reach a verdict.
  case incomplete

  /// No result exists for the route at all.
  case unverified

  /// Results exist, but none for the route's current fingerprint.
  case stale

  /// The result for the current fingerprint is a pass.
  case verified

  /// A use case that is not fully written yet has no verification state. No route has this.
  case draft

  /// Where the state is listed: `0` is first, which is the worst.
  public var reportRank: Int {
    Self.allCases.firstIndex(of: self) ?? Self.allCases.count
  }

  /// The state a verdict gives a route.
  init(verdict: Verdict) {
    switch verdict {
    case .pass:
      self = .verified
    case .fail:
      self = .failed
    case .incomplete:
      self = .incomplete
    case .error:
      self = .error
    }
  }
}
