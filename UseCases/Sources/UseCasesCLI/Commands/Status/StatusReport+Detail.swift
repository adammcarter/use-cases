import UseCasesCore

extension StatusReport {
  /// One use case in detail (chapter 16 §9): every route, whether it gates, its state and why,
  /// then its sign-off, its warnings and the hint.
  func detailText(
    of useCase: UseCaseStatus,
    hint: Bool,
  ) -> String {
    var lines = [
      "\(useCase.status.marked)  \(useCase.identifier) · \(useCase.title)",
    ]

    if let reason = useCase.listingReason(shortening: workspace.runIdentifiers), !useCase.isReady {
      lines += ["", reason]
    }

    if !useCase.routes.isEmpty {
      lines += [""] + table(of: useCase.routes)
    }

    let signOff = signOffLine(of: useCase)
    if let signOff {
      lines += ["", signOff]
    }

    let warnings = useCase.warnings.map { warning in
      "warning: \(warning.text)"
    }
    if !warnings.isEmpty {
      lines += [""] + warnings
    }

    if hint, let line = detailHint(of: useCase) {
      lines += ["", line]
    }

    return lines.joined(separator: "\n")
  }

  private func table(of routes: [RouteStatus]) -> [String] {
    let routeWidth = max(
      "route".count,
      routes.map(\.identifier.count).max() ?? 0,
    ) + 2

    let header = row(
      "route",
      "gates",
      "status",
      "why",
      routeWidth: routeWidth,
    )

    return [header] + routes.map { route in
      row(
        route.identifier,
        route.gates ? "yes" : "no",
        route.status.marked,
        route.explanation.text(shortening: workspace.runIdentifiers),
        routeWidth: routeWidth,
      )
    }
  }

  private func row(
    _ route: String,
    _ gates: String,
    _ status: String,
    _ why: String,
    routeWidth: Int,
  ) -> String {
    "  " + route.padded(toWidth: routeWidth) + gates.padded(toWidth: 8)
      + status.padded(toWidth: 16) + why
  }

  /// The sign-off of the use case (chapter 21). That a use case is not approved is said only
  /// where the root requires sign-off: elsewhere it is the normal case and there is nothing to say.
  private func signOffLine(of useCase: UseCaseStatus) -> String? {
    let day = useCase.approvedOn.map { day in
      "on \(day)"
    }
    let who = [useCase.approver, day]
      .compactMap(\.self)
      .joined(separator: " ")

    switch useCase.approval {
    case .approved:
      return "sign-off: approved by \(who)"
    case .changed:
      return "sign-off: changed since approved (by \(who))"
    case .unapproved:
      return workspace.signOffRequired && useCase.isReady ? "sign-off: not approved" : nil
    }
  }

  private func detailHint(of useCase: UseCaseStatus) -> String? {
    switch useCase.status {
    case .failed, .error, .incomplete:
      hintLine("\(verifyStep)   once it is fixed")
    case .stale, .unverified:
      hintLine(verifyStep)
    case .verified, .draft:
      nil
    }
  }
}
