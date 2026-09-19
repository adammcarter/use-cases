/// Deterministic presentation planning
/// (packages/core/src/presentation/selectPlan.ts, selectShowcasePlan.ts and
/// selectWalkthroughPlan.ts).
///
/// Two things reach outside: the clock, read only when the request carries no
/// `generatedAt`, and `use-cases.yml`, read as text for the workflow snapshot.
public enum PresentationPlanner {
  /// The placeholder hash a plan carries before it is hashed, and its
  /// `working_tree_digest`.
  public static let zeroHash = "sha256:" + String(repeating: "0", count: 64)

  /// `selectShowcasePlan`.
  public static func selectShowcasePlan(
    context: ResolvedWorkspaceContext,
    matrix: MatrixSnapshot,
    evidence: EvidenceSnapshot,
    request: PresentationPlanRequest,
    clock: any PresentationClock = SystemPresentationClock(),
  ) throws(PresentationError) -> PresentationPlanResult {
    try selectPlan(
      context: context,
      matrix: matrix,
      evidence: evidence,
      request: request,
      profile: .showcase,
      clock: clock,
    )
  }

  /// `selectWalkthroughPlan`.
  public static func selectWalkthroughPlan(
    context: ResolvedWorkspaceContext,
    matrix: MatrixSnapshot,
    evidence: EvidenceSnapshot,
    request: PresentationPlanRequest,
    clock: any PresentationClock = SystemPresentationClock(),
  ) throws(PresentationError) -> PresentationPlanResult {
    try selectPlan(
      context: context,
      matrix: matrix,
      evidence: evidence,
      request: request,
      profile: .walkthrough,
      clock: clock,
    )
  }

  /// `selectPlan`. Strict mode on incomplete input blocks before eligibility
  /// is considered; every candidate neither selected nor excluded on its own
  /// is reported as `max_items`, even when the timebox left it out.
  public static func selectPlan(
    context: ResolvedWorkspaceContext,
    matrix: MatrixSnapshot,
    evidence: EvidenceSnapshot,
    request: PresentationPlanRequest,
    profile: SelectionProfile,
    clock: any PresentationClock = SystemPresentationClock(),
  ) throws(PresentationError) -> PresentationPlanResult {
    let inputs = Inputs(
      context: context,
      matrix: matrix,
      evidence: evidence,
      request: request,
      profile: profile,
      generatedAt: request.generatedAt
        ?? JavaScriptTimestamp.isoString(milliseconds: clock.milliseconds()),
    )
    let candidates = PresentationCandidates.build(
      matrix: matrix,
      request: request,
      profile: profile,
      hostSurface: inputs.hostSurface,
    )
    let eligible = candidates.filter(\.isEligible)

    if request.isStrict, inputs.isIncompleteInput {
      return result(
        .integrityBlocked,
        plan: nil,
        candidates: candidates,
        selected: [],
        inputs: inputs,
      )
    }
    if eligible.isEmpty {
      return result(
        .noEligibleItems,
        plan: nil,
        candidates: candidates,
        selected: [],
        inputs: inputs,
      )
    }

    let selected = selectWithinLimits(eligible, inputs: inputs)
    let workflow = try readWorkflow(context: context)
    let plan = assemble(inputs, candidates: candidates, selected: selected, workflow: workflow)
    return result(
      .generated,
      plan: plan,
      candidates: candidates,
      selected: selected,
      inputs: inputs,
    )
  }

  /// Eligible candidates in the mode's order, taken while they fit.
  private static func selectWithinLimits(
    _ eligible: [PresentationCandidate],
    inputs: Inputs,
  ) -> [PresentationCandidate] {
    let ordered = inputs.profile.mode == .walkthrough
      ? PresentationOrdering.walkthrough(eligible)
      : PresentationScoring.sorted(eligible)
    return PresentationOrdering.withinLimits(
      ordered,
      estimatedSeconds: inputs.profile.fallbackEstimateSeconds,
      maxItems: inputs.maxItems,
      timeboxSeconds: inputs.timeboxSeconds,
    )
  }

  private static func readWorkflow(
    context: ResolvedWorkspaceContext,
  ) throws(PresentationError) -> WorkflowSnapshot {
    do {
      return try PresentationSnapshot.workflowSnapshot(context: context)
    } catch {
      throw .fileAccess(error)
    }
  }

  /// `computePresentationPlanHash`: the semantic hash of a plan without its
  /// `plan_id`, `generated_at` and `plan_content_hash`. Takes the plan as JSON
  /// so a plan read back from a file hashes the same way.
  public static func planContentHash(of plan: JSONObject) -> String {
    var stable = plan
    stable["plan_id"] = nil
    stable["generated_at"] = nil
    stable["plan_content_hash"] = nil
    return SemanticHash.compute(.object(stable))
  }

  /// Everything one selection reads, with the profile's defaults applied: a
  /// timebox of zero or NaN (JavaScript `||`) and an absent cap (JavaScript
  /// `??`) fall back.
  private struct Inputs {
    let context: ResolvedWorkspaceContext
    let matrix: MatrixSnapshot
    let evidence: EvidenceSnapshot
    let request: PresentationPlanRequest
    let profile: SelectionProfile
    let generatedAt: String
    let hostSurface: String
    let timeboxSeconds: Double
    let maxItems: Double
    let isIncompleteInput: Bool

    init(
      context: ResolvedWorkspaceContext,
      matrix: MatrixSnapshot,
      evidence: EvidenceSnapshot,
      request: PresentationPlanRequest,
      profile: SelectionProfile,
      generatedAt: String,
    ) {
      self.context = context
      self.matrix = matrix
      self.evidence = evidence
      self.request = request
      self.profile = profile
      self.generatedAt = generatedAt
      hostSurface = request.hostSurface ?? "unknown"
      let timebox = request.timeboxSeconds
      timeboxSeconds = timebox == 0 || timebox.isNaN ? profile.defaultTimeboxSeconds : timebox
      maxItems = request.maxItems ?? profile.defaultMaxItems
      isIncompleteInput = !matrix.isComplete || !evidence.isComplete
    }

    var freshnessEvaluatedAt: String {
      request.freshnessEvaluatedAt ?? generatedAt
    }
  }

  /// The freshness policy's digest: `{ semanticHashMismatch: "needs_review" }`.
  private static let freshnessPolicyDigest = SemanticHash.compute(.object(JSONObject([
    ("semanticHashMismatch", .string("needs_review")),
  ])))

  private static func assemble(
    _ inputs: Inputs,
    candidates: [PresentationCandidate],
    selected: [PresentationCandidate],
    workflow: WorkflowSnapshot,
  ) -> PresentationPlan {
    let items = selected.map { candidate in
      PresentationPlanItems.item(for: candidate, evidence: inputs.evidence, profile: inputs.profile)
    }
    let plan = PresentationPlan(
      planIdentifier: PresentationSnapshot.planIdentifier(
        mode: inputs.profile.mode,
        generatedAt: inputs.generatedAt,
      ),
      planContentHash: zeroHash,
      generatedAt: inputs.generatedAt,
      mode: inputs.profile.mode,
      isComplete: !inputs.isIncompleteInput,
      readiness: readiness(inputs, items: items),
      integrityAcknowledgementRequired: inputs.isIncompleteInput,
      selectionProfileIdentifier: inputs.profile.identifier,
      selectionProfileDigest: SemanticHash.compute(inputs.profile.digestValue),
      inputSnapshot: inputSnapshot(inputs, items: items, workflow: workflow),
      componentIdentifier: inputs.context.componentIdentifier,
      capturedAt: inputs.freshnessEvaluatedAt,
      audience: inputs.request.audience,
      timeboxSeconds: inputs.timeboxSeconds,
      sections: PresentationPlanItems.sections(mode: inputs.profile.mode, items: items),
      selectedItems: items,
      exclusions: exclusions(candidates, selected: selected),
      knownGaps: PresentationPlanItems.planGaps(isIncompleteInput: inputs.isIncompleteInput),
    )
    let planObject = plan.jsonValue.objectValue ?? JSONObject()
    return plan.withContentHash(planContentHash(of: planObject))
  }

  /// Every candidate not selected, in matrix order, with its own exclusion or
  /// the item-cap one.
  private static func exclusions(
    _ candidates: [PresentationCandidate],
    selected: [PresentationCandidate],
  ) -> [PresentationPlanExclusion] {
    let selectedIdentifiers = PresentationCandidates.identifierKeys(selected)
    return candidates
      .filter { candidate in
        !selectedIdentifiers.contains(CodeUnitKey(candidate.useCase.identifier))
      }
      .map { candidate in
        candidate.exclusion
          ?? PresentationCandidates.capacityExclusion(
            for: candidate.useCase,
            reasonCode: "max_items",
          )
      }
  }

  private static func readiness(
    _ inputs: Inputs,
    items: [PresentationPlanItem],
  ) -> PlanReadiness {
    if inputs.isIncompleteInput {
      return .partialDueToIntegrity
    }
    let hasEvidenceGap = items.contains { item in
      item.knownGaps.contains { gap in
        gap.severity != .info
      }
    }
    return hasEvidenceGap ? .readyWithEvidenceGaps : .ready
  }

  private static func inputSnapshot(
    _ inputs: Inputs,
    items: [PresentationPlanItem],
    workflow: WorkflowSnapshot,
  ) -> PlanInputSnapshot {
    PlanInputSnapshot(
      matrixDigest: PresentationSnapshot.matrixDigest(inputs.matrix),
      evidenceBasisDigest: PresentationSnapshot.evidenceDigest(
        inputs.evidence,
        useCaseIdentifiers: items.map(\.useCaseIdentifier),
      ),
      changedPaths: PresentationPlanHelpers.normalizedPaths(inputs.request.changedPaths),
      freshnessPolicyIdentifier: "default-v1",
      freshnessPolicyDigest: freshnessPolicyDigest,
      freshnessEvaluatedAt: inputs.freshnessEvaluatedAt,
      hostSurface: inputs.hostSurface,
      workflow: workflow,
    )
  }

  private static func result(
    _ outcome: PresentationPlanOutcome,
    plan: PresentationPlan?,
    candidates: [PresentationCandidate],
    selected: [PresentationCandidate],
    inputs: Inputs,
  ) -> PresentationPlanResult {
    PresentationPlanResult(
      outcome: outcome,
      plan: plan,
      candidateSummary: PresentationCandidates.summary(candidates, selected: selected),
      matrixIntegrity: inputs.matrix.integrity.state,
      evidenceIntegrity: inputs.evidence.integrity.state,
    )
  }
}
