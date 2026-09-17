/// How serious a known gap is.
public enum PlanGapSeverity: String, Sendable, Equatable {
  case info
  case warning
  case error
}

/// Something a plan or item cannot yet claim.
public struct PlanGap: Sendable, Equatable {
  public let code: String
  public let message: String
  public let severity: PlanGapSeverity

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("code", .string(code)),
      ("message", .string(message)),
      ("severity", .string(severity.rawValue)),
    ]))
  }
}

/// Whether evidence for a requirement was seen.
public enum RequiredEvidenceStatus: String, Sendable, Equatable {
  case candidateObserved = "candidate_observed"
  case missing
  case unknownDueToIntegrity = "unknown_due_to_integrity"
  case notApplicable = "not_applicable"
}

/// One verification requirement an item carries into the live run.
public struct RequiredEvidenceSummary: Sendable, Equatable {
  public let evidenceKind: String
  public let requiredVerifiers: [String]
  /// Any JSON number the row's policy holds.
  public let minimumCount: Double
  public let status: RequiredEvidenceStatus

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("evidence_kind", .string(evidenceKind)),
      ("required_verifiers", .array(requiredVerifiers.map(JSONValue.string))),
      ("minimum_count", .number(minimumCount)),
      ("status", .string(status.rawValue)),
    ]))
  }
}

/// How ready an item's evidence is.
public enum EvidenceReadiness: String, Sendable, Equatable {
  case availableCurrent = "available_current"
  case availableStale = "available_stale"
  case missing
  case invalid
  case unknown
  case ambiguous
}

/// How fresh an item's evidence is.
public enum FreshnessState: String, Sendable, Equatable {
  case current
  case needsReview = "needs_review"
  case stale
  case unknown
  case invalidated
}

/// Whether an item covers its row whole or named scenarios.
public enum ScenarioScope: String, Sendable, Equatable {
  case wholeUseCase = "whole_use_case"
  case explicit
}

/// Where an item's time estimate came from.
public enum EstimateSource: String, Sendable, Equatable {
  case useCase = "use_case"
  case defaultProfile = "default_profile"
}

/// An item's evidence, summarised.
public struct ItemEvidenceSummary: Sendable, Equatable {
  public let readiness: EvidenceReadiness
  public let activeEvidenceIdentifiers: [String]
  public let basis: String
}

/// An item's freshness, summarised.
public struct ItemFreshnessSummary: Sendable, Equatable {
  public let state: FreshnessState
  public let basis: String
}

/// The ranking a candidate was scored with. A rank is nil when the row's value
/// is not one the table knows — `undefined` in the TypeScript, which drops the
/// member from the wire and makes the comparator call the pair equal.
public struct ScoreComponents: Sendable, Equatable {
  public let changed: Int
  public let value: Int?
  public let journey: Int?
  public let frequency: Int?

  var jsonValue: JSONValue {
    var object = JSONObject()
    object["changed"] = .number(Double(changed))
    object["value"] = value.map(rank)
    object["journey"] = journey.map(rank)
    object["frequency"] = frequency.map(rank)
    return .object(object)
  }

  private func rank(_ value: Int) -> JSONValue {
    .number(Double(value))
  }
}

/// One selected item, fully resolved (`PresentationPlanItem`).
public struct PresentationPlanItem: Sendable, Equatable {
  public let planItemIdentifier: String
  /// The chosen format: the source of truth for how the item is shown.
  public let presentationFormat: PresentationFormat
  /// The legacy projection of ``presentationFormat``.
  public let deliveryKind: DeliveryKind
  public let scenarioScope: ScenarioScope
  public let useCaseIdentifier: String
  /// The row's title, the card heading. Nil falls back to the id.
  public let useCaseTitle: String?
  public let scenarioIdentifiers: [String]
  public let useCaseContentHash: String
  public let estimatedSeconds: Double
  public let estimateSource: EstimateSource
  public let setupSteps: [String]
  public let resolvedSteps: [String]
  public let expectedObservations: [String]
  public let teardownSteps: [String]
  public let requiredPermissions: [String]
  public let safetyConstraints: [String]
  public let verificationPolicySnapshot: JSONObject
  public let approvalPolicySnapshot: JSONObject
  public let approvalResolutionRequiredAtRunStart: Bool
  public let requiredEvidence: [RequiredEvidenceSummary]
  public let evidenceSummary: ItemEvidenceSummary
  public let freshnessSummary: ItemFreshnessSummary
  public let knownGaps: [PlanGap]
  public let selectionReasons: [String]
  public let selectionReasonCodes: [String]
  public let scoreComponents: ScoreComponents

  public init(
    planItemIdentifier: String,
    presentationFormat: PresentationFormat,
    deliveryKind: DeliveryKind,
    scenarioScope: ScenarioScope,
    useCaseIdentifier: String,
    useCaseTitle: String?,
    scenarioIdentifiers: [String],
    useCaseContentHash: String,
    estimatedSeconds: Double,
    estimateSource: EstimateSource,
    setupSteps: [String],
    resolvedSteps: [String],
    expectedObservations: [String],
    teardownSteps: [String],
    requiredPermissions: [String],
    safetyConstraints: [String],
    verificationPolicySnapshot: JSONObject,
    approvalPolicySnapshot: JSONObject,
    approvalResolutionRequiredAtRunStart: Bool,
    requiredEvidence: [RequiredEvidenceSummary],
    evidenceSummary: ItemEvidenceSummary,
    freshnessSummary: ItemFreshnessSummary,
    knownGaps: [PlanGap],
    selectionReasons: [String],
    selectionReasonCodes: [String],
    scoreComponents: ScoreComponents,
  ) {
    self.planItemIdentifier = planItemIdentifier
    self.presentationFormat = presentationFormat
    self.deliveryKind = deliveryKind
    self.scenarioScope = scenarioScope
    self.useCaseIdentifier = useCaseIdentifier
    self.useCaseTitle = useCaseTitle
    self.scenarioIdentifiers = scenarioIdentifiers
    self.useCaseContentHash = useCaseContentHash
    self.estimatedSeconds = estimatedSeconds
    self.estimateSource = estimateSource
    self.setupSteps = setupSteps
    self.resolvedSteps = resolvedSteps
    self.expectedObservations = expectedObservations
    self.teardownSteps = teardownSteps
    self.requiredPermissions = requiredPermissions
    self.safetyConstraints = safetyConstraints
    self.verificationPolicySnapshot = verificationPolicySnapshot
    self.approvalPolicySnapshot = approvalPolicySnapshot
    self.approvalResolutionRequiredAtRunStart = approvalResolutionRequiredAtRunStart
    self.requiredEvidence = requiredEvidence
    self.evidenceSummary = evidenceSummary
    self.freshnessSummary = freshnessSummary
    self.knownGaps = knownGaps
    self.selectionReasons = selectionReasons
    self.selectionReasonCodes = selectionReasonCodes
    self.scoreComponents = scoreComponents
  }

  /// The wire item, members in `toPlanItem`'s order.
  public var jsonValue: JSONValue {
    var object = JSONObject()
    object["plan_item_id"] = .string(planItemIdentifier)
    object["presentation_format"] = .string(presentationFormat.rawValue)
    object["delivery_kind"] = .string(deliveryKind.rawValue)
    object["scenario_scope"] = .string(scenarioScope.rawValue)
    object["use_case_id"] = .string(useCaseIdentifier)
    object["use_case_title"] = useCaseTitle.map(JSONValue.string)
    object["scenario_ids"] = strings(scenarioIdentifiers)
    object["use_case_content_hash"] = .string(useCaseContentHash)
    object["estimated_seconds"] = .number(estimatedSeconds)
    object["estimate_source"] = .string(estimateSource.rawValue)
    object["setup_steps"] = strings(setupSteps)
    object["resolved_steps"] = strings(resolvedSteps)
    object["expected_observations"] = strings(expectedObservations)
    object["teardown_steps"] = strings(teardownSteps)
    object["required_permissions"] = strings(requiredPermissions)
    object["safety_constraints"] = strings(safetyConstraints)
    object["verification_policy_snapshot"] = .object(verificationPolicySnapshot)
    object["approval_policy_snapshot"] = .object(approvalPolicySnapshot)
    object["approval_resolution_required_at_run_start"] =
      .bool(approvalResolutionRequiredAtRunStart)
    object["required_evidence"] = .array(requiredEvidence.map(\.jsonValue))
    object["evidence_summary"] = .object(JSONObject([
      ("readiness", .string(evidenceSummary.readiness.rawValue)),
      ("active_evidence_ids", strings(evidenceSummary.activeEvidenceIdentifiers)),
      ("basis", .string(evidenceSummary.basis)),
    ]))
    object["freshness_summary"] = .object(JSONObject([
      ("state", .string(freshnessSummary.state.rawValue)),
      ("basis", .string(freshnessSummary.basis)),
    ]))
    object["known_gaps"] = .array(knownGaps.map(\.jsonValue))
    object["selection_reasons"] = strings(selectionReasons)
    object["selection_reason_codes"] = strings(selectionReasonCodes)
    object["score_components"] = scoreComponents.jsonValue
    return .object(object)
  }

  private func strings(_ values: [String]) -> JSONValue {
    .array(values.map(JSONValue.string))
  }
}
