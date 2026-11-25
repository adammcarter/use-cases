extension WorkspaceStatus {
  /// What the gate says about every use case of the workspace (chapter 16 §10).
  ///
  /// Failed, error and stale block; incomplete and unverified warn, and block under `strict`.
  /// Drafts never block. With `sign_off: required`, a READY use case whose promise is not approved
  /// as it reads now is held too: critical blocks, the other tiers warn, and `strict` blocks all
  /// three. A use case's status is already the worst of its gating routes, so a route that does
  /// not gate never reaches the gate.
  ///
  /// - Parameter strict: Whether everything not verified must be proven.
  public func gate(strict: Bool) -> Gate {
    var blocking: [GateEntry] = []
    var warning: [GateEntry] = []

    for useCase in useCases {
      let held = holdLevel(
        of: useCase,
        strict: strict,
      )
      let byStatus = Self.level(
        of: useCase.status,
        strict: strict,
      )

      let level = max(
        byStatus,
        held,
      )

      guard level != .passes else {
        continue
      }

      let entry = GateEntry(
        useCase: useCase.identifier,
        status: useCase.status,
        reason: byStatus >= held ? .status(useCase.status) : .notApproved,
        heldForApproval: held == .passes ? nil : useCase.approval,
      )

      if level == .blocks {
        blocking.append(entry)
      } else {
        warning.append(entry)
      }
    }

    return Gate(
      isStrict: strict,
      blocking: blocking,
      warning: warning,
    )
  }

  /// What the sign-off requirement does to a use case, apart from its state.
  private func holdLevel(
    of useCase: UseCaseStatus,
    strict: Bool,
  ) -> GateLevel {
    guard signOffRequired, useCase.isReady, useCase.approval != .approved else {
      return .passes
    }

    guard !strict, useCase.valueTier != "critical" else {
      return .blocks
    }

    return .warns
  }

  private static func level(
    of status: VerificationStatus,
    strict: Bool,
  ) -> GateLevel {
    switch status {
    case .failed, .error, .stale:
      .blocks
    case .incomplete, .unverified:
      strict ? .blocks : .warns
    case .verified, .draft:
      .passes
    }
  }
}

private enum GateLevel: Int, Comparable {
  case passes
  case warns
  case blocks

  static func < (
    lhs: GateLevel,
    rhs: GateLevel,
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
