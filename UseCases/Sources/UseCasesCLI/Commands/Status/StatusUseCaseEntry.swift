import UseCasesCore

/// One use case in the status document (`cli-status.schema.json`, `useCase`). A DRAFT has
/// `missing` and no routes; a READY use case has routes and no `missing`.
struct StatusUseCaseEntry: Encodable {
  let useCase: String
  let title: String
  let state: String
  let status: String

  /// Present for a DRAFT only.
  let missing: [String]?
  let warnings: [String]
  let routes: [StatusRouteEntry]
  let approval: String

  /// Absent when the use case has not chosen a tier.
  let valueTier: String?

  enum CodingKeys: String, CodingKey {
    case useCase = "use_case"
    case title
    case state
    case status
    case missing
    case warnings
    case routes
    case approval
    case valueTier = "value_tier"
  }

  init(_ useCase: UseCaseStatus) {
    self.useCase = useCase.identifier
    title = useCase.title
    state = useCase.isReady ? "READY" : "DRAFT"
    status = useCase.status.rawValue
    missing = useCase.isReady ? nil : useCase.missing
    warnings = useCase.warnings.map(\.text)
    routes = useCase.routes.map(StatusRouteEntry.init)
    approval = useCase.approval.rawValue
    valueTier = useCase.valueTier
  }
}
