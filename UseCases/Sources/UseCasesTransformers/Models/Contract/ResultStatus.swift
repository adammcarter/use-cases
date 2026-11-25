/// The four results a transformer reports, with the same meaning from every transformer
/// (chapter 10 §13).
enum ResultStatus: String, Codable, Equatable, Sendable {
  case pass
  case fail
  case error
  case incomplete

  /// The worst of `statuses`: fail, then error, then incomplete, then pass. Nil for none.
  static func worst(of statuses: [ResultStatus]) -> ResultStatus? {
    statuses.max { first, second in
      first.severity < second.severity
    }
  }

  private var severity: Int {
    switch self {
    case .pass: 0
    case .incomplete: 1
    case .error: 2
    case .fail: 3
    }
  }
}
