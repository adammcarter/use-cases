extension StatusJudge {
  /// One use case, DRAFT or READY.
  func status(
    of useCase: LoadedUseCase,
    using inputs: StatusInputs,
  ) throws(StatusJudgingError) -> UseCaseStatus {
    let definition = useCase.definition
    let identifier = useCase.identifier.text
    let approval = try ApprovalState(
      approval: definition.approval,
      promise: promiseFingerprint(of: useCase),
    )
    let emptyRegions = markedRegionWarnings(
      of: identifier,
      using: inputs,
    )

    switch definition.authoredState {
    case let .draft(missing):
      return UseCaseStatus(
        identifier: identifier,
        title: definition.title,
        status: .draft,
        missing: missing.map(\.words),
        routes: [],
        approval: approval,
        approver: definition.approval?.approver,
        approvedOn: definition.approval?.day,
        valueTier: definition.valueTier?.rawValue,
        warnings: emptyRegions,
      )
    case .ready:
      let routes = try routes(
        of: useCase,
        using: inputs,
      )

      return UseCaseStatus(
        identifier: identifier,
        title: definition.title,
        status: Self.worst(of: routes),
        missing: [],
        routes: routes,
        approval: approval,
        approver: definition.approval?.approver,
        approvedOn: definition.approval?.day,
        valueTier: definition.valueTier?.rawValue,
        warnings: emptyRegions + linkWarnings(
          of: useCase,
          routes: routes,
          using: inputs,
        ),
      )
    }
  }

  /// The empty marked regions of the use case, each as its own warning.
  private func markedRegionWarnings(
    of identifier: String,
    using inputs: StatusInputs,
  ) -> [UseCaseWarning] {
    inputs.emptyRegions
      .filter { region in
        region.useCase == identifier
      }
      .map { region in
        UseCaseWarning(
          kind: .markedRegionEmpty,
          text: region.text,
        )
      }
  }

  /// The routes of a READY use case, as written.
  private func routes(
    of useCase: LoadedUseCase,
    using inputs: StatusInputs,
  ) throws(StatusJudgingError) -> [RouteStatus] {
    var judged: [RouteStatus] = []

    for route in useCase.definition.routes {
      let fingerprint = try currentFingerprint(
        of: route,
        in: useCase,
        using: inputs,
      )
      let judgement = inputs.history.judgement(
        useCase: useCase.identifier,
        route: route.identifier,
        fingerprint: fingerprint,
      )

      judged.append(
        RouteStatus(
          identifier: route.identifier.text,
          gates: route.gatesVerification,
          isLinked: route.procedure != nil || inputs.coverage.hasValidationLink(
            useCase: useCase.identifier.text,
            route: route.identifier.text,
          ),
          status: judgement.status,
          explanation: judgement.explanation,
        ),
      )
    }

    return judged
  }

  /// The use case shows the worst state among its gating routes; a route that does not gate keeps
  /// its own state and cannot lower it (chapter 07 "Overall READY status").
  private static func worst(of routes: [RouteStatus]) -> VerificationStatus {
    routes
      .filter(\.gates)
      .map(\.status)
      .min { lhs, rhs in
        lhs.reportRank < rhs.reportRank
      } ?? .verified
  }

  private func currentFingerprint(
    of route: ValidationRoute,
    in useCase: LoadedUseCase,
    using inputs: StatusInputs,
  ) throws(StatusJudgingError) -> RouteFingerprint {
    guard let text = inputs.fingerprints.fingerprint(
      useCase: useCase.identifier.text,
      route: route.identifier.text,
    ) else {
      throw .fingerprint(
        "route \(route.identifier.text) of \(useCase.identifier.text) has no fingerprint",
      )
    }

    do {
      return try RouteFingerprint(validating: text)
    } catch {
      throw .fingerprint("\(error)")
    }
  }

  private func promiseFingerprint(of useCase: LoadedUseCase) throws(StatusJudgingError) -> String {
    do {
      return try promiseFingerprinter.fingerprint(
        of: PromiseFingerprintInput(
          definition: useCase.definition,
          identifier: useCase.identifier,
        ),
      )
    } catch {
      throw .fingerprint(
        "the promise of \(useCase.identifier.text) could not be fingerprinted: \(error)",
      )
    }
  }

  /// A READY use case with nothing tying it to code, or a gating route nothing can reach, is
  /// told so (chapter 08 "Cardinality"). Neither stops it being judged.
  private func linkWarnings(
    of useCase: LoadedUseCase,
    routes: [RouteStatus],
    using inputs: StatusInputs,
  ) -> [UseCaseWarning] {
    var warnings: [UseCaseWarning] = []

    if !inputs.coverage.hasImplementationLink(useCase: useCase.identifier.text) {
      warnings.append(
        UseCaseWarning(
          kind: .noImplementationLinks,
          text: "no implementation links, so freshness does not track its code",
        ),
      )
    }

    for route in routes where route.gates && !route.isLinked {
      warnings.append(
        UseCaseWarning(
          kind: .routeNotLinked,
          text: "route \(route.identifier) has no validation links and no procedure, "
            + "so only `use-cases record` can verify it",
        ),
      )
    }

    return warnings
  }
}
