/// Where a binding came from, which content-and-locator mode fingerprints (chapter 11 §38,
/// §89.5).
enum LinkContributionKind: String, Sendable {
  case marker
  case manual
  case transformer

  /// The kind of a link the core resolved.
  init(source: LinkSource) {
    switch source {
    case .marker: self = .marker
    case .manual: self = .manual
    case .transformer: self = .transformer
    }
  }
}
