/// One use case as `status` shows it: READY with its routes judged, or DRAFT with what it lacks.
public struct UseCaseStatus: Equatable, Sendable {
  /// The full id.
  public let identifier: String

  public let title: String

  /// The state the use case is listed in: its worst gating route, or `draft`.
  public let status: VerificationStatus

  /// What a DRAFT lacks before it is READY, in the order a reader fills it in; empty for a READY
  /// use case.
  public let missing: [String]

  /// Every route of a READY use case, as written; empty for a DRAFT.
  public let routes: [RouteStatus]

  /// Whether its promise is signed off as it reads now.
  public let approval: ApprovalState

  /// Who signed off, when anyone did.
  public let approver: String?

  /// The day of the sign-off, `YYYY-MM-DD`, when there is one.
  public let approvedOn: String?

  /// `critical`, `core` or `supporting`; `nil` when the use case has not chosen one.
  public let valueTier: String?

  public let warnings: [UseCaseWarning]

  /// Whether the use case is fully written.
  public var isReady: Bool {
    status != .draft
  }

  /// The gating route that gave the use case its status: the first, as written, with the worst
  /// state. `nil` for a DRAFT, and for a READY use case with no gating route.
  public var decidingRoute: RouteStatus? {
    routes.first { route in
      route.gates && route.status == status
    }
  }
}
