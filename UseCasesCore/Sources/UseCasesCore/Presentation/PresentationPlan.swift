/// How ready a generated plan is to run.
public enum PlanReadiness: String, Sendable, Equatable {
  case ready
  case readyWithEvidenceGaps = "ready_with_evidence_gaps"
  case partialDueToIntegrity = "partial_due_to_integrity"
  case blocked
}

/// What planning produced.
public enum PresentationPlanOutcome: String, Sendable, Equatable {
  case generated
  case noEligibleItems = "no_eligible_items"
  case integrityBlocked = "integrity_blocked"
}

/// A titled run of items.
public struct PresentationPlanSection: Sendable, Equatable {
  public let sectionIdentifier: String
  public let title: String
  public let purpose: String
  public let itemIdentifiers: [String]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("section_id", .string(sectionIdentifier)),
      ("title", .string(title)),
      ("purpose", .string(purpose)),
      ("item_ids", .array(itemIdentifiers.map(JSONValue.string))),
    ]))
  }
}

/// A row left out of the plan, and why.
public struct PresentationPlanExclusion: Sendable, Equatable {
  public let useCaseIdentifier: String
  public let reasonCode: String
  public let reason: String
  public let isBlocking: Bool

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("use_case_id", .string(useCaseIdentifier)),
      ("reason_code", .string(reasonCode)),
      ("reason", .string(reason)),
      ("blocking", .bool(isBlocking)),
    ]))
  }
}

/// Where the workflow mode in a plan came from.
public enum WorkflowSource: String, Sendable, Equatable {
  case `default`
  case workspaceConfig = "workspace_config"
}

/// The advisory workflow mode read from `use-cases.yml`.
public struct WorkflowSnapshot: Sendable, Equatable {
  public let effectiveMode: String
  public let source: WorkflowSource
}

/// The inputs a plan was generated from.
public struct PlanInputSnapshot: Sendable, Equatable {
  public let matrixDigest: String
  public let evidenceBasisDigest: String
  public let changedPaths: [String]
  public let freshnessPolicyIdentifier: String
  public let freshnessPolicyDigest: String
  public let freshnessEvaluatedAt: String
  public let hostSurface: String
  public let workflow: WorkflowSnapshot
}

/// A prepared presentation plan (`PresentationPlan`). The constant members —
/// `schema_version`, `prepared_not_performed`, `selection_method`, the profile
/// version, the workflow's `advisory` and the unknown workspace facts — are
/// written by ``jsonValue`` rather than stored.
public struct PresentationPlan: Sendable, Equatable {
  public let planIdentifier: String
  public let planContentHash: String
  public let generatedAt: String
  public let mode: PresentationMode
  public let isComplete: Bool
  public let readiness: PlanReadiness
  public let integrityAcknowledgementRequired: Bool
  public let selectionProfileIdentifier: String
  public let selectionProfileDigest: String
  public let inputSnapshot: PlanInputSnapshot
  public let componentIdentifier: String
  /// The workspace snapshot's `captured_at`: the freshness evaluation time.
  public let capturedAt: String
  public let audience: String
  public let timeboxSeconds: Double
  public let sections: [PresentationPlanSection]
  public let selectedItems: [PresentationPlanItem]
  public let exclusions: [PresentationPlanExclusion]
  public let knownGaps: [PlanGap]

  /// A copy carrying `hash` as its content hash.
  func withContentHash(_ hash: String) -> PresentationPlan {
    PresentationPlan(
      planIdentifier: planIdentifier,
      planContentHash: hash,
      generatedAt: generatedAt,
      mode: mode,
      isComplete: isComplete,
      readiness: readiness,
      integrityAcknowledgementRequired: integrityAcknowledgementRequired,
      selectionProfileIdentifier: selectionProfileIdentifier,
      selectionProfileDigest: selectionProfileDigest,
      inputSnapshot: inputSnapshot,
      componentIdentifier: componentIdentifier,
      capturedAt: capturedAt,
      audience: audience,
      timeboxSeconds: timeboxSeconds,
      sections: sections,
      selectedItems: selectedItems,
      exclusions: exclusions,
      knownGaps: knownGaps,
    )
  }

  /// The wire plan, members in `selectPlan`'s literal order.
  /// `plan_content_hash` stays third: the TypeScript spreads the hashless plan
  /// and re-assigns that member, which keeps its place.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("plan_id", .string(planIdentifier)),
      ("plan_content_hash", .string(planContentHash)),
      ("generated_at", .string(generatedAt)),
      ("mode", .string(mode.rawValue)),
      ("complete", .bool(isComplete)),
      ("prepared_not_performed", .bool(true)),
      ("readiness", .string(readiness.rawValue)),
      ("integrity_acknowledgement_required", .bool(integrityAcknowledgementRequired)),
      ("selection_method", .string("deterministic")),
      ("selection_profile", .object(JSONObject([
        ("id", .string(selectionProfileIdentifier)),
        ("version", .number(1)),
        ("digest", .string(selectionProfileDigest)),
      ]))),
      ("input_snapshot", inputSnapshotValue),
      ("workspace_snapshot", workspaceSnapshotValue),
      ("environment_expectations", .object(JSONObject([
        ("host_surfaces", .array([.string(inputSnapshot.hostSurface)])),
      ]))),
      ("audience", .string(audience)),
      ("timebox_seconds", .number(timeboxSeconds)),
      ("sections", .array(sections.map(\.jsonValue))),
      ("selected_items", .array(selectedItems.map(\.jsonValue))),
      ("exclusions", .array(exclusions.map(\.jsonValue))),
      ("known_gaps", .array(knownGaps.map(\.jsonValue))),
    ]))
  }

  private var inputSnapshotValue: JSONValue {
    .object(JSONObject([
      ("matrix_digest", .string(inputSnapshot.matrixDigest)),
      ("evidence_basis_digest", .string(inputSnapshot.evidenceBasisDigest)),
      ("changed_paths", .array(inputSnapshot.changedPaths.map(JSONValue.string))),
      ("freshness_policy", .object(JSONObject([
        ("id", .string(inputSnapshot.freshnessPolicyIdentifier)),
        ("digest", .string(inputSnapshot.freshnessPolicyDigest)),
        ("evaluated_at", .string(inputSnapshot.freshnessEvaluatedAt)),
      ]))),
      ("host_surface", .string(inputSnapshot.hostSurface)),
      ("workflow", .object(JSONObject([
        ("effective_mode", .string(inputSnapshot.workflow.effectiveMode)),
        ("source", .string(inputSnapshot.workflow.source.rawValue)),
        ("advisory", .bool(true)),
      ]))),
    ]))
  }

  private var workspaceSnapshotValue: JSONValue {
    .object(JSONObject([
      ("repository_id", .string("unknown")),
      ("vcs", .string("unknown")),
      ("head_revision", .string("unknown")),
      ("dirty", .bool(false)),
      ("working_tree_digest", .string(PresentationPlanner.zeroHash)),
      ("component_id", .string(componentIdentifier)),
      ("captured_at", .string(capturedAt)),
    ]))
  }
}

/// One reason code and how many rows it excluded.
public struct ExclusionReasonCount: Sendable, Equatable {
  public let reasonCode: String
  public let count: Int
}

/// How many rows were considered, and what became of them.
public struct CandidateSummary: Sendable, Equatable {
  public let considered: Int
  public let eligible: Int
  public let selected: Int
  public let excluded: Int
  /// Reason codes with their counts, in the order each code was first met.
  public let excludedByReason: [ExclusionReasonCount]

  var jsonValue: JSONValue {
    var reasons = JSONObject()
    for entry in excludedByReason {
      reasons[entry.reasonCode] = .number(Double(entry.count))
    }
    return .object(JSONObject([
      ("considered", .number(Double(considered))),
      ("eligible", .number(Double(eligible))),
      ("selected", .number(Double(selected))),
      ("excluded", .number(Double(excluded))),
      ("excluded_by_reason", .object(reasons)),
    ]))
  }
}

/// What planning returns (`PresentationPlanResult`).
public struct PresentationPlanResult: Sendable, Equatable {
  public let outcome: PresentationPlanOutcome
  /// Present only when ``outcome`` is `generated`.
  public let plan: PresentationPlan?
  public let candidateSummary: CandidateSummary
  public let matrixIntegrity: MatrixIntegrityState
  public let evidenceIntegrity: EvidenceIntegrityState

  /// The wire result.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("outcome", .string(outcome.rawValue)),
      ("plan", plan?.jsonValue ?? .null),
      ("candidate_summary", candidateSummary.jsonValue),
      ("input_integrity", .object(JSONObject([
        ("matrix", .string(matrixIntegrity.rawValue)),
        ("evidence", .string(evidenceIntegrity.rawValue)),
      ]))),
    ]))
  }
}
