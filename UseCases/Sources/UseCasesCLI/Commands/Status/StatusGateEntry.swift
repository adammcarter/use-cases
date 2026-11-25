import UseCasesCore

/// A use case the gate blocks on or warns about, in the status document (`gated`).
struct StatusGateEntry: Encodable {
  let useCase: String
  let status: String

  /// `changed` or `unapproved`, present only when the sign-off is what holds the use case.
  let approval: String?

  enum CodingKeys: String, CodingKey {
    case useCase = "use_case"
    case status
    case approval
  }

  init(_ entry: GateEntry) {
    useCase = entry.useCase
    status = entry.status.rawValue
    approval = entry.heldForApproval?.rawValue
  }
}
