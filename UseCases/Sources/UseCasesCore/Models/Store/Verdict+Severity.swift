extension Verdict {
  /// How bad the verdict is when several tests fall inside one link: `fail`, then `error`, then
  /// `incomplete`, then `pass` (chapter 10 §13). The greater, the worse.
  var severity: Int {
    switch self {
    case .fail:
      3
    case .error:
      2
    case .incomplete:
      1
    case .pass:
      0
    }
  }

  /// The worse of two verdicts.
  func worse(than other: Verdict) -> Verdict {
    severity >= other.severity ? self : other
  }
}
