/// One addressable row, scored and judged (`PresentationCandidate`).
struct PresentationCandidate {
  let useCase: LoadedUseCase
  let isEligible: Bool
  let exclusion: PresentationPlanExclusion?
  let isChanged: Bool
  let scoreComponents: ScoreComponents
  let reasonCodes: [String]
  let reasons: [String]
}

/// Turning addressable rows into candidates, deciding which are eligible, and
/// summarising what became of them
/// (packages/core/src/presentation/candidates.ts).
enum PresentationCandidates {
  /// `buildCandidates`, in the matrix's addressable order.
  static func build(
    matrix: MatrixSnapshot,
    request: PresentationPlanRequest,
    profile: SelectionProfile,
    hostSurface: String,
  ) -> [PresentationCandidate] {
    let requested = Set(request.requestedUseCaseIdentifiers.map(CodeUnitKey.init))
    return matrix.addressableUseCases.map { useCase in
      let isChanged = matchesChangedPath(useCase, changedPaths: request.changedPaths)
      let hardExclusion = hardEligibilityExclusion(useCase, hostSurface: hostSurface)
      let requestExclusion = !requested.isEmpty && !requested
        .contains(CodeUnitKey(useCase.identifier))
        ? exclusion(
          for: useCase,
          reasonCode: "not_requested",
          reason: "Use case was not requested for this plan.",
          isBlocking: false,
        )
        : nil
      let reasons = PresentationScoring.reasons(useCase, isChanged: isChanged, mode: profile.mode)
      return PresentationCandidate(
        useCase: useCase,
        isEligible: hardExclusion == nil && requestExclusion == nil,
        exclusion: hardExclusion ?? requestExclusion,
        isChanged: isChanged,
        scoreComponents: PresentationScoring.score(
          useCase,
          mode: profile.mode,
          isChanged: isChanged,
        ),
        reasonCodes: reasons.codes,
        reasons: reasons.reasons,
      )
    }
  }

  /// `summarizeCandidates`. A row neither selected nor carrying an exclusion
  /// is counted under `max_items` — whatever actually left it out.
  static func summary(
    _ candidates: [PresentationCandidate],
    selected: [PresentationCandidate],
  ) -> CandidateSummary {
    let selectedIdentifiers = identifierKeys(selected)
    let excluded = candidates.filter { candidate in
      !selectedIdentifiers.contains(CodeUnitKey(candidate.useCase.identifier))
    }
    var counts: [ExclusionReasonCount] = []
    for candidate in excluded {
      let reasonCode = candidate.exclusion?.reasonCode ?? "max_items"
      if let index = counts.firstIndex(where: { $0.reasonCode == reasonCode }) {
        counts[index] = ExclusionReasonCount(reasonCode: reasonCode, count: counts[index].count + 1)
      } else {
        counts.append(ExclusionReasonCount(reasonCode: reasonCode, count: 1))
      }
    }
    return CandidateSummary(
      considered: candidates.count,
      eligible: candidates.count(where: \.isEligible),
      selected: selected.count,
      excluded: excluded.count,
      excludedByReason: counts,
    )
  }

  /// `exclusionFor`: a row that lost to higher-priority items. Only `timebox`
  /// has its own wording; the planner never passes it (see
  /// docs/rewrite/scenario-conventions.md), so every such row reads as the cap.
  static func capacityExclusion(
    for useCase: LoadedUseCase,
    reasonCode: String,
  ) -> PresentationPlanExclusion {
    exclusion(
      for: useCase,
      reasonCode: reasonCode,
      reason: reasonCode == "timebox"
        ? "Higher-priority items consumed the available timebox."
        : "Higher-priority items consumed the available item cap.",
      isBlocking: false,
    )
  }

  /// `hardEligibilityExclusion`: lifecycle, then host, then runnability.
  private static func hardEligibilityExclusion(
    _ useCase: LoadedUseCase,
    hostSurface: String,
  ) -> PresentationPlanExclusion? {
    if useCase.value["lifecycle"]?.stringValue != "active" {
      return exclusion(
        for: useCase,
        reasonCode: "lifecycle",
        reason: "Only active use cases are eligible by default.",
        isBlocking: true,
      )
    }
    if !hostMatches(useCase, hostSurface: hostSurface) {
      return exclusion(
        for: useCase,
        reasonCode: "host_surface",
        reason: "Use case is not supported on \(hostSurface).",
        isBlocking: true,
      )
    }
    if PresentationPlanHelpers.resolvedSteps(useCase).isEmpty
      || PresentationPlanHelpers.expectedObservations(useCase).isEmpty
    {
      return exclusion(
        for: useCase,
        reasonCode: "not_runnable",
        reason: "Use case lacks runnable steps or expected observations.",
        isBlocking: true,
      )
    }
    return nil
  }

  /// `hostMatches`: an unknown host, or a row naming no hosts, matches.
  private static func hostMatches(
    _ useCase: LoadedUseCase,
    hostSurface: String,
  ) -> Bool {
    let hosts = useCase.value["host_applicability"]?.arrayValue ?? []
    if hostSurface == "unknown" || hosts.isEmpty {
      return true
    }
    return hosts.contains { host in
      guard let surface = host["host_surface"]?.stringValue else {
        return false
      }
      return PresentationPlanHelpers.sameCodeUnits(surface, hostSurface) && host["supported"]?
        .boolValue == true
    }
  }

  /// `matchesChangedPath`: a `file` source ref whose normalised path is one of
  /// the normalised changed paths, compared by code unit.
  private static func matchesChangedPath(
    _ useCase: LoadedUseCase,
    changedPaths: [String],
  ) -> Bool {
    if changedPaths.isEmpty {
      return false
    }
    let changed = Set(PresentationPlanHelpers.normalizedPaths(changedPaths).map(CodeUnitKey.init))
    return (useCase.value["source_refs"]?.arrayValue ?? []).contains { sourceReference in
      guard sourceReference["kind"]?.stringValue == "file",
            let path = sourceReference["path"]?.stringValue
      else {
        return false
      }
      return changed.contains(CodeUnitKey(PresentationPlanHelpers.normalizedPath(path)))
    }
  }

  /// The candidates' use-case ids, as JavaScript `Set` members.
  static func identifierKeys(_ candidates: [PresentationCandidate]) -> Set<CodeUnitKey> {
    Set(candidates.map(\.useCase.identifier).map(CodeUnitKey.init))
  }

  private static func exclusion(
    for useCase: LoadedUseCase,
    reasonCode: String,
    reason: String,
    isBlocking: Bool,
  ) -> PresentationPlanExclusion {
    PresentationPlanExclusion(
      useCaseIdentifier: useCase.identifier,
      reasonCode: reasonCode,
      reason: reason,
      isBlocking: isBlocking,
    )
  }
}
