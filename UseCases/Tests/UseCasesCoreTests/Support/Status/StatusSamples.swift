@testable import UseCasesCore

/// Statuses of use cases and workspaces, built by hand for the tests of what is done with them.
enum StatusSamples {
  static func route(
    _ identifier: String = "unit-tests",
    status: VerificationStatus = .verified,
    gates: Bool = true,
  ) -> RouteStatus {
    RouteStatus(
      identifier: identifier,
      gates: gates,
      isLinked: true,
      status: status,
      explanation: .noVerdictYet,
    )
  }

  /// A READY use case whose one gating route has this state.
  static func useCase(
    _ identifier: String,
    _ status: VerificationStatus = .verified,
    tier: String? = "core",
    approval: ApprovalState = .approved,
    routes: [RouteStatus]? = nil,
  ) -> UseCaseStatus {
    UseCaseStatus(
      identifier: identifier,
      title: identifier,
      status: status,
      missing: status == .draft ? ["intent"] : [],
      routes: status == .draft ? [] : routes ?? [route(status: status)],
      approval: approval,
      approver: approval == .unapproved ? nil : "Sam",
      approvedOn: approval == .unapproved ? nil : "2026-10-19",
      valueTier: tier,
      warnings: [],
    )
  }

  static func workspace(
    _ useCases: [UseCaseStatus],
    signOffRequired: Bool = false,
    hasSealedRuns: Bool = true,
    warnings: [WorkspaceWarning] = [],
    hasRunCommand: Bool = false,
    store: StoreSummary? = nil,
    runIdentifiers: RunIdentifierShortener = RunIdentifierShortener(runs: []),
  ) -> WorkspaceStatus {
    WorkspaceStatus(
      useCases: useCases,
      warnings: warnings,
      hasSealedRuns: hasSealedRuns,
      signOffRequired: signOffRequired,
      hasRunCommand: hasRunCommand,
      store: store,
      runIdentifiers: runIdentifiers,
    )
  }
}
