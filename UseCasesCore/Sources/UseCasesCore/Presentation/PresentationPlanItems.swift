/// Turning a selected candidate into a resolved plan item, and the sections
/// and plan-level gaps built from the items
/// (packages/core/src/presentation/items.ts).
enum PresentationPlanItems {
  /// `toPlanItem`.
  static func item(
    for candidate: PresentationCandidate,
    evidence: EvidenceSnapshot,
    profile: SelectionProfile,
  ) -> PresentationPlanItem {
    let useCase = candidate.useCase
    let summary = evidenceSummary(evidence, useCase: useCase)
    let requiredEvidence = requiredEvidence(useCase, status: summary.status)
    let baseDeliveryKind = baseDeliveryKind(useCase, mode: profile.mode)
    let format = PresentationFormat.choose(
      baseDeliveryKind: baseDeliveryKind,
      needsUser: needsUserActor(useCase),
      // v1 auto-selection never picks `comparing` or `inspecting`.
      isContrast: false,
    )
    let approvalPolicy = PresentationPlanHelpers.policySnapshot(useCase.value["approval_policy"])
    let scenarios = useCase.value["scenarios"]?.arrayValue ?? []
    return PresentationPlanItem(
      planItemIdentifier: "item.\(useCase.identifier)",
      presentationFormat: format,
      deliveryKind: format.deliveryKind(base: baseDeliveryKind),
      scenarioScope: scenarios.isEmpty ? .wholeUseCase : .explicit,
      useCaseIdentifier: useCase.identifier,
      useCaseTitle: useCase.value["title"]?.stringValue,
      scenarioIdentifiers: scenarios.map { $0["id"]?.stringValue ?? "" },
      useCaseContentHash: useCase.semanticHash,
      estimatedSeconds: profile.fallbackEstimateSeconds,
      estimateSource: .defaultProfile,
      setupSteps: [],
      resolvedSteps: PresentationPlanHelpers.resolvedSteps(useCase),
      expectedObservations: PresentationPlanHelpers.expectedObservations(useCase),
      teardownSteps: [],
      requiredPermissions: [],
      safetyConstraints: [],
      verificationPolicySnapshot: PresentationPlanHelpers
        .policySnapshot(useCase.value["verification_policy"]),
      approvalPolicySnapshot: approvalPolicy,
      approvalResolutionRequiredAtRunStart: approvalPolicy["mode"]?.stringValue == "ask",
      requiredEvidence: requiredEvidence,
      evidenceSummary: ItemEvidenceSummary(
        readiness: summary.readiness,
        activeEvidenceIdentifiers: summary.activeEvidenceIdentifiers,
        basis: summary.basis,
      ),
      freshnessSummary: ItemFreshnessSummary(
        state: summary.freshnessState,
        basis: summary.freshnessBasis,
      ),
      knownGaps: gaps(useCase, readiness: summary.readiness, requiredEvidence: requiredEvidence),
      selectionReasons: candidate.reasons,
      selectionReasonCodes: candidate.reasonCodes,
      scoreComponents: candidate.scoreComponents,
    )
  }

  /// `planGaps`.
  static func planGaps(isIncompleteInput: Bool) -> [PlanGap] {
    if isIncompleteInput {
      return [PlanGap(
        code: "input_integrity_partial",
        message: "The plan was generated from partial input and requires acknowledgement "
          + "before execution.",
        severity: .warning,
      )]
    }
    return [PlanGap(
      code: "prepared_not_performed",
      message: "The plan is prepared only; no live run has been performed.",
      severity: .info,
    )]
  }

  /// `sectionsFor`. A walkthrough's primary path is the items whose use-case
  /// id contains `.golden` — or the first item when none does; its coverage is
  /// the rest — or every item when nothing is left.
  static func sections(
    mode: PresentationMode,
    items: [PresentationPlanItem],
  ) -> [PresentationPlanSection] {
    let allIdentifiers = items.map(\.planItemIdentifier)
    guard mode == .walkthrough else {
      return [PresentationPlanSection(
        sectionIdentifier: "section.primary-path",
        title: "Primary path",
        purpose: "Show the highest-value user-visible behavior.",
        itemIdentifiers: allIdentifiers,
      )]
    }
    let primary = items
      .filter { item in
        item.useCaseIdentifier.utf16.containsSubsequence(".golden".utf16)
      }
      .map(\.planItemIdentifier)
    let primaryKeys = Set(primary.map(CodeUnitKey.init))
    let coverage = allIdentifiers.filter { identifier in
      !primaryKeys.contains(CodeUnitKey(identifier))
    }
    return [
      PresentationPlanSection(
        sectionIdentifier: "section.primary-path",
        title: "Primary path",
        purpose: "Establish the main product value.",
        itemIdentifiers: primary.isEmpty ? Array(allIdentifiers.prefix(1)) : primary,
      ),
      PresentationPlanSection(
        sectionIdentifier: "section.coverage",
        title: "Coverage",
        purpose: "Walk through alternate, edge, negative, and failure behavior.",
        itemIdentifiers: coverage.isEmpty ? allIdentifiers : coverage,
      ),
    ]
  }

  /// `baseDeliveryKindFor`. The TypeScript gives showcase its own live-demo
  /// check before falling back to `deliveryKindFor`, which makes the same
  /// check first — so both modes reduce to the one projection, and `mode`
  /// cannot change the answer.
  private static func baseDeliveryKind(
    _ useCase: LoadedUseCase,
    mode _: PresentationMode,
  ) -> DeliveryKind {
    let requirements = PresentationPlanHelpers.verificationRequirements(useCase)
    if requirements.contains(where: { $0.evidenceKind == "live_demo" }) {
      return .liveDemo
    }
    return requirements.isEmpty ? .explanation : .evidenceReview
  }

  /// A requirement naming the `user` verifier, or an approval policy in `ask`
  /// mode, needs a human.
  private static func needsUserActor(_ useCase: LoadedUseCase) -> Bool {
    let requirements = PresentationPlanHelpers.verificationRequirements(useCase)
    let namesUser = requirements.contains { requirement in
      requirement.requiredVerifiers.contains("user")
    }
    if namesUser {
      return true
    }
    return PresentationPlanHelpers.policySnapshot(useCase.value["approval_policy"])["mode"]?
      .stringValue == "ask"
  }

  private struct EvidenceFacts {
    let readiness: EvidenceReadiness
    let activeEvidenceIdentifiers: [String]
    let status: RequiredEvidenceStatus
    let basis: String
    let freshnessState: FreshnessState
    let freshnessBasis: String
  }

  /// `evidenceForUseCase`.
  private static func evidenceSummary(
    _ evidence: EvidenceSnapshot,
    useCase: LoadedUseCase,
  ) -> EvidenceFacts {
    if !evidence.isComplete, evidence.integrity.hasUnknownScopeDamage {
      return EvidenceFacts(
        readiness: .unknown,
        activeEvidenceIdentifiers: [],
        status: .unknownDueToIntegrity,
        basis: "evidence_integrity_incomplete",
        freshnessState: .unknown,
        freshnessBasis: "evidence_integrity_incomplete",
      )
    }
    let matching = evidence.aggregates.filter { aggregate in
      aggregate.status == .active && aggregate.targetLinks.contains { target in
        targets(target, useCase: useCase)
      }
    }
    if matching.isEmpty {
      return EvidenceFacts(
        readiness: .missing,
        activeEvidenceIdentifiers: [],
        status: .missing,
        basis: "no_active_evidence",
        freshnessState: .unknown,
        freshnessBasis: "missing_evidence",
      )
    }
    let semanticMatches = matching.contains { aggregate in
      aggregate.targetLinks.contains { target in
        guard targets(target, useCase: useCase),
              let hash = target["use_case_semantic_hash"]?.stringValue
        else {
          return false
        }
        return PresentationPlanHelpers.sameCodeUnits(hash, useCase.semanticHash)
      }
    }
    return EvidenceFacts(
      readiness: semanticMatches ? .availableCurrent : .availableStale,
      activeEvidenceIdentifiers: matching.map(\.evidenceIdentifier),
      status: .candidateObserved,
      basis: semanticMatches ? "active_evidence_semantic_hash_match" :
        "active_evidence_semantic_hash_mismatch",
      freshnessState: semanticMatches ? .current : .needsReview,
      freshnessBasis: semanticMatches ? "policy_match" : "use_case_semantic_hash_mismatch",
    )
  }

  private static func targets(
    _ target: JSONValue,
    useCase: LoadedUseCase,
  ) -> Bool {
    guard let identifier = target["use_case_id"]?.stringValue else {
      return false
    }
    return PresentationPlanHelpers.sameCodeUnits(identifier, useCase.identifier)
  }

  /// `requiredEvidenceFor`: a row without requirements carries one
  /// not-applicable manual observation.
  private static func requiredEvidence(
    _ useCase: LoadedUseCase,
    status: RequiredEvidenceStatus,
  ) -> [RequiredEvidenceSummary] {
    let requirements = PresentationPlanHelpers.verificationRequirements(useCase)
    if requirements.isEmpty {
      return [RequiredEvidenceSummary(
        evidenceKind: "manual_observation",
        requiredVerifiers: [],
        minimumCount: 1,
        status: .notApplicable,
      )]
    }
    return requirements.map { requirement in
      RequiredEvidenceSummary(
        evidenceKind: requirement.evidenceKind,
        requiredVerifiers: requirement.requiredVerifiers,
        minimumCount: requirement.minimumCount,
        status: status,
      )
    }
  }

  /// `gapsForItem`.
  private static func gaps(
    _ useCase: LoadedUseCase,
    readiness: EvidenceReadiness,
    requiredEvidence: [RequiredEvidenceSummary],
  ) -> [PlanGap] {
    var gaps: [PlanGap] = []
    if requiredEvidence.contains(where: { $0.status == .missing }) {
      gaps.append(PlanGap(
        code: "evidence_missing",
        message: "Required evidence is missing; live performance is still required.",
        severity: .warning,
      ))
    }
    if readiness == .availableStale {
      gaps.append(PlanGap(
        code: "evidence_needs_review",
        message: "Existing evidence targets an older use-case semantic hash.",
        severity: .warning,
      ))
    }
    if PresentationPlanHelpers.policySnapshot(useCase.value["approval_policy"])["mode"]?
      .stringValue == "ask"
    {
      gaps.append(PlanGap(
        code: "approval_resolution_required",
        message: "Approval policy must be resolved during the later live run.",
        severity: .info,
      ))
    }
    if gaps.isEmpty {
      gaps.append(PlanGap(
        code: "prepared_not_performed",
        message: "This is a prepared plan and has not been performed.",
        severity: .info,
      ))
    }
    return gaps
  }
}

private extension Sequence where Element: Equatable {
  /// True when `needle` appears as a contiguous run.
  func containsSubsequence(_ needle: some Collection<Element>) -> Bool {
    let haystack = Array(self)
    let needle = Array(needle)
    guard needle.count <= haystack.count else {
      return false
    }
    return (0 ... haystack.count - needle.count).contains { start in
      haystack[start ..< start + needle.count].elementsEqual(needle)
    }
  }
}
