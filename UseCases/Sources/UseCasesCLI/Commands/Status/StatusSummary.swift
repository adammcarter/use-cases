import UseCasesCore

/// How many use cases are shown, and how many are in each state.
struct StatusSummary: Encodable {
  let total: Int

  /// The states with at least one use case; the others are left out.
  let byStatus: [String: Int]

  enum CodingKeys: String, CodingKey {
    case total
    case byStatus = "by_status"
  }

  init(_ useCases: [UseCaseStatus]) {
    total = useCases.count
    byStatus = Dictionary(
      grouping: useCases,
      by: \.status.rawValue,
    ).mapValues(\.count)
  }

  /// `1 failed`, `2 stale`: the states with at least one use case, worst first.
  var counts: [String] {
    VerificationStatus.allCases.compactMap { status in
      byStatus[status.rawValue].map { count in
        "\(count) \(status.rawValue)"
      }
    }
  }
}
