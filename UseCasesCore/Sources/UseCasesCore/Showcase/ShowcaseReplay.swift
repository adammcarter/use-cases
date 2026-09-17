/// One plan item's state after replay (`ShowcaseItemStatus`). Members copied
/// from ledger lines keep whatever JSON the line held; nil is `undefined`,
/// which leaves the member out of the wire form.
public struct ShowcaseItemStatus: Equatable, Sendable {
  public var planItemIdentifier: JSONValue?
  public var verdict: JSONValue?
  public var itemCurrency: String
  public var verificationState: String
  public var latestObservationEventIdentifier: JSONValue?
  public var latestVerdictEventIdentifier: JSONValue?

  /// `initialItem`.
  init(planItemIdentifier: JSONValue?) {
    self.planItemIdentifier = planItemIdentifier
    verdict = .string("none")
    itemCurrency = "unknown"
    verificationState = "requirements_unmet"
    latestObservationEventIdentifier = .null
    latestVerdictEventIdentifier = .null
  }

  public var jsonValue: JSONValue {
    var object = JSONObject()
    object["plan_item_id"] = planItemIdentifier
    object["verdict"] = verdict
    object["item_currency"] = .string(itemCurrency)
    object["verification_state"] = .string(verificationState)
    object["latest_observation_event_id"] = latestObservationEventIdentifier
    object["latest_verdict_event_id"] = latestVerdictEventIdentifier
    return .object(object)
  }
}

/// A run's status derived from its events (`ShowcaseRunStatus`).
public struct ShowcaseRunStatus: Equatable, Sendable {
  public let runIdentifier: JSONValue?
  public let isComplete: Bool
  public let executionStatus: String
  public let runOutcome: String
  public let approvalState: String
  public let unresolvedFailureCount: Int
  /// The verified approver, when the approval state rests on a verified token.
  public let approval: (actorType: JSONValue?, assuranceTier: AssuranceTier)?
  public let items: [ShowcaseItemStatus]
  /// The plan's `known_gaps`, whatever JSON it is.
  public let knownGaps: JSONValue
  public let ignoredApprovalEvents: [JSONValue?]

  public static func == (
    left: ShowcaseRunStatus,
    right: ShowcaseRunStatus,
  ) -> Bool {
    left.jsonValue == right.jsonValue
  }

  public var jsonValue: JSONValue {
    var object = JSONObject()
    object["schema_version"] = .number(1)
    object["run_id"] = runIdentifier
    object["complete"] = .bool(isComplete)
    object["execution_status"] = .string(executionStatus)
    object["run_outcome"] = .string(runOutcome)
    object["approval_state"] = .string(approvalState)
    object["unresolved_failure_count"] = .number(Double(unresolvedFailureCount))
    if let approval {
      var approver = JSONObject()
      approver["actor_type"] = approval.actorType
      approver["assurance_tier"] = .string(approval.assuranceTier.rawValue)
      object["approval"] = .object(approver)
    }
    object["items"] = .array(items.map(\.jsonValue))
    object["known_gaps"] = knownGaps
    var diagnostics = JSONObject()
    if !ignoredApprovalEvents.isEmpty {
      diagnostics["ignored_approval_events"] = .array(ignoredApprovalEvents.map { $0 ?? .null })
    }
    object["diagnostic_summary"] = .object(diagnostics)
    return .object(object)
  }
}

/// Replays a run's events into its status (showcase/replayRun.ts).
public enum ShowcaseReplay {
  /// `replayShowcaseRun`: read the ledger, then replay it with its own
  /// completeness.
  public static func replay(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
    trust: ShowcaseTrustResolvers = .none,
  ) throws(ShowcaseError) -> ShowcaseRunStatus {
    let read = try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier)
    return try replay(
      runIdentifier: .string(runIdentifier),
      events: read.events,
      isLedgerComplete: read.isComplete,
      trust: trust,
    )
  }

  /// `replayShowcaseEvents`.
  public static func replay(
    runIdentifier: JSONValue?,
    events: [JSONValue],
    isLedgerComplete: Bool = true,
    trust resolvers: ShowcaseTrustResolvers = .none,
  ) throws(ShowcaseError) -> ShowcaseRunStatus {
    let ordered = try ShowcaseJavaScript.sortedBySequence(events)
    let start = try ApprovalBinding.first(in: ordered, ofType: "run_started")
    let plan: JSONValue? = if let start {
      try ShowcaseJavaScript.member(ShowcaseJavaScript.member(start, "payload"), "plan")
    } else {
      nil
    }
    let trust = try ApprovalTrust(
      resolvers: resolvers,
      assuranceFloor: ApprovalPolicy.assuranceFloor(forPlan: plan),
    )
    var state = try ReplayState(plan: plan)

    for event in ordered {
      try state.apply(event, trust: trust)
    }
    return try state.status(
      runIdentifier: runIdentifier,
      isLedgerComplete: isLedgerComplete,
      plan: plan,
    )
  }
}

/// The event types replay acts on, compared by code unit.
private enum ReplayEventKind: String, CaseIterable {
  case actionRecorded = "action_recorded"
  case observationRecorded = "observation_recorded"
  case verdictRecorded = "verdict_recorded"
  case failureDecisionRecorded = "failure_decision_recorded"
  case verdictCorrected = "verdict_corrected"
  case epochStarted = "epoch_started"
  case runPaused = "run_paused"
  case runResumed = "run_resumed"
  case runFinished = "run_finished"
  case approvalRecorded = "approval_recorded"
  case approvalRejected = "approval_rejected"

  /// The kind an `event_type` value names, if any.
  static func of(_ type: JSONValue?) -> ReplayEventKind? {
    allCases.first { kind in
      ShowcaseJavaScript.isString(type, kind.rawValue)
    }
  }
}

/// The running fold over ordered events. The TypeScript tests an event's type
/// against each handler in turn; a type names at most one, so each event is
/// dispatched once, after the two checks every event gets.
private struct ReplayState {
  var items: [ShowcaseItemStatus]
  var unresolvedFailures = JavaScriptValueSet()
  var verdictEventItems: [CodeUnitKey: JSONValue?] = [:]
  var hasPerformedEvent = false
  var isPaused = false
  var isAborted = false
  var isFinished = false
  var approvalState: String
  var isOutcomeChangedAfterApproval = false
  var approvedSequence: JSONValue? = .number(0)
  var approval: (actorType: JSONValue?, assuranceTier: AssuranceTier)?
  var ignoredApprovalEvents: [JSONValue?] = []

  init(plan: JSONValue?) throws(ShowcaseError) {
    let selected = try ShowcaseJavaScript.arrayOrEmpty(
      ShowcaseJavaScript.optionalMember(plan, "selected_items"),
      calling: "map",
    )
    var items: [ShowcaseItemStatus] = []
    for item in selected {
      let identifier = try ShowcaseJavaScript.member(item, "plan_item_id")
      items.append(ShowcaseItemStatus(planItemIdentifier: identifier))
    }
    self.items = items
    approvalState = try ApprovalPolicy.requiresUserApproval(plan: plan) ? "pending" : "not_required"
  }

  /// `byItem.get(key)`: the Map was built from the items in order, so a
  /// repeated id maps to the LAST item carrying it; only a string id is ever
  /// found by a string key.
  func itemIndex(_ key: JSONValue?) -> Int? {
    guard case let .string(text) = key else {
      return nil
    }
    return items.lastIndex { item in
      ShowcaseJavaScript.isString(item.planItemIdentifier, text)
    }
  }

  mutating func apply(
    _ event: JSONValue,
    trust: ApprovalTrust,
  ) throws(ShowcaseError) {
    let type = try ShowcaseJavaScript.member(event, "event_type")
    let sequence = try ShowcaseJavaScript.member(event, "sequence")
    let kind = ReplayEventKind.of(type)

    if kind == .actionRecorded || kind == .observationRecorded {
      hasPerformedEvent = true
    }
    if ShowcaseJavaScript.greaterThan(approvedSequence, .number(0)),
       ShowcaseJavaScript.greaterThan(sequence, approvedSequence),
       Self.affectsApproval(type)
    {
      isOutcomeChangedAfterApproval = true
    }
    try applyEvidence(kind, event)
    applyLifecycle(kind)
    try applyApproval(kind, event, sequence: sequence, trust: trust)
  }

  private mutating func applyEvidence(
    _ kind: ReplayEventKind?,
    _ event: JSONValue,
  ) throws(ShowcaseError) {
    switch kind {
    case .observationRecorded:
      if let index = try itemIndex(.string(Self.payloadText(event, "plan_item_id"))) {
        items[index].latestObservationEventIdentifier = try ShowcaseJavaScript.member(
          event,
          "event_id",
        )
      }
    case .verdictRecorded:
      try recordVerdict(event, verdictKey: "verdict", currency: "current")
    case .failureDecisionRecorded:
      try recordFailureDecision(event)
    case .verdictCorrected:
      try recordVerdict(event, verdictKey: "corrected_verdict", currency: "corrected")
    case .epochStarted:
      try recordEpoch(event)
    default:
      break
    }
  }

  private mutating func applyLifecycle(_ kind: ReplayEventKind?) {
    switch kind {
    case .runPaused:
      isPaused = true
    case .runResumed:
      isPaused = false
    case .runFinished:
      isFinished = true
    default:
      break
    }
  }

  /// A user's approval or rejection counts only when its token verifies; a
  /// rejection by anyone else counts without one.
  private mutating func applyApproval(
    _ kind: ReplayEventKind?,
    _ event: JSONValue,
    sequence: JSONValue?,
    trust: ApprovalTrust,
  ) throws(ShowcaseError) {
    guard kind == .approvalRecorded || kind == .approvalRejected else {
      return
    }
    if let verified = try trust.trustedDecision(event) {
      if kind == .approvalRecorded {
        let payload = try ShowcaseJavaScript.member(event, "payload")
        let decision = try ShowcaseJavaScript.member(payload, "decision")
        approvalState = ShowcaseJavaScript.isString(decision, "approved_with_known_gaps")
          ? "approved_with_known_gaps" : "approved"
      } else {
        approvalState = "rejected"
      }
      approvedSequence = sequence
      approval = (verified.actorType, verified.assuranceTier)
    } else if kind == .approvalRejected, try trust.isTrustedDecisionEvent(event) {
      approvalState = "rejected"
      approvedSequence = sequence
      approval = nil
    } else {
      try ignoredApprovalEvents.append(ShowcaseJavaScript.member(event, "event_id"))
    }
  }

  /// A `verdict_recorded` (the item's `verdict`) or `verdict_corrected` (its
  /// `corrected_verdict`, after releasing the corrected verdict's failure).
  private mutating func recordVerdict(
    _ event: JSONValue,
    verdictKey: String,
    currency: String,
  ) throws(ShowcaseError) {
    let payload = try ShowcaseJavaScript.member(event, "payload")
    let planItem = try ShowcaseJavaScript.member(payload, "plan_item_id")
    guard let index = itemIndex(.string(JavaScriptString.text(of: planItem))) else {
      return
    }
    if verdictKey == "corrected_verdict" {
      let target = try ShowcaseJavaScript.member(payload, "target_event_id")
      unresolvedFailures.remove(.string(JavaScriptString.text(of: target)))
    }
    let eventIdentifier = try ShowcaseJavaScript.member(event, "event_id")
    items[index].verdict = try ShowcaseJavaScript.member(payload, verdictKey)
    items[index].latestVerdictEventIdentifier = eventIdentifier
    if case let .string(text) = eventIdentifier {
      verdictEventItems[CodeUnitKey(text)] = items[index].planItemIdentifier
    }
    items[index].itemCurrency = currency
    items[index].verificationState = ShowcaseJavaScript.isString(items[index].verdict, "pass")
      ? "requirements_met" : "requirements_unmet"
    if Self.isFailure(items[index].verdict) {
      unresolvedFailures.insert(eventIdentifier)
    }
  }

  private mutating func recordFailureDecision(_ event: JSONValue) throws(ShowcaseError) {
    let payload = try ShowcaseJavaScript.member(event, "payload")
    let verdictEvent = try ShowcaseJavaScript.member(payload, "verdict_event_id")
    let verdictEventIdentifier = JavaScriptString.text(of: verdictEvent)
    unresolvedFailures.remove(.string(verdictEventIdentifier))
    let planItemIdentifier = verdictEventItems[CodeUnitKey(verdictEventIdentifier)].flatMap(\.self)
    let index = JavaScriptValue.isTruthy(planItemIdentifier) ? itemIndex(planItemIdentifier) : nil
    let decision = try ShowcaseJavaScript.member(payload, "decision")
    if let index, ShowcaseJavaScript.isString(decision, "waive_with_reason") {
      items[index].verdict = .string("waived")
      items[index].verificationState = "not_required"
    }
    if ShowcaseJavaScript.isString(decision, "pause_to_fix") {
      isPaused = true
    }
    if ShowcaseJavaScript.isString(decision, "abort") {
      isAborted = true
    }
  }

  private mutating func recordEpoch(_ event: JSONValue) throws(ShowcaseError) {
    let payload = try ShowcaseJavaScript.member(event, "payload")
    let staleItems = try ShowcaseJavaScript.member(payload, "stale_item_ids")
    for planItemIdentifier in try ShowcaseJavaScript.iterated(staleItems) {
      guard let index = itemIndex(planItemIdentifier) else {
        continue
      }
      items[index].itemCurrency = "stale_due_to_epoch_change"
      items[index].verificationState = "stale"
    }
  }

  /// `String(event.payload.<key>)`.
  private static func payloadText(
    _ event: JSONValue,
    _ key: String,
  ) throws(ShowcaseError) -> String {
    let payload = try ShowcaseJavaScript.member(event, "payload")
    return try JavaScriptString.text(of: ShowcaseJavaScript.member(payload, key))
  }

  private static func isFailure(_ verdict: JSONValue?) -> Bool {
    ShowcaseJavaScript.isString(verdict, "fail") || ShowcaseJavaScript.isString(verdict, "blocked")
  }

  /// `affectsApproval`.
  private static func affectsApproval(_ type: JSONValue?) -> Bool {
    let affecting = [
      "observation_recorded",
      "verdict_recorded",
      "failure_decision_recorded",
      "epoch_started",
      "carry_forward_recorded",
      "run_finished",
      "observation_corrected",
      "verdict_corrected",
      "failure_decision_corrected",
      "carry_forward_corrected",
      "finish_corrected",
    ]
    return affecting.contains { name in
      ShowcaseJavaScript.isString(type, name)
    }
  }

  private func anyItem(withVerdict verdict: String) -> Bool {
    items.contains { item in
      ShowcaseJavaScript.isString(item.verdict, verdict)
    }
  }

  private var anyStale: Bool {
    items.contains { item in
      item.itemCurrency == "stale_due_to_epoch_change"
    }
  }

  private var executionStatus: String {
    if !hasPerformedEvent {
      "prepared_not_performed"
    } else if isAborted {
      "aborted"
    } else if isFinished, !anyStale {
      "completed"
    } else if isPaused {
      "paused"
    } else {
      "running"
    }
  }

  private var runOutcome: String {
    let allPassed = !items.isEmpty && items.allSatisfy { item in
      ShowcaseJavaScript.isString(item.verdict, "pass")
    }
    return if !hasPerformedEvent {
      "prepared_not_performed"
    } else if isAborted {
      "aborted"
    } else if anyStale {
      "incomplete"
    } else if anyItem(withVerdict: "blocked") {
      "blocked"
    } else if anyItem(withVerdict: "fail") {
      "failed"
    } else if anyItem(withVerdict: "waived") {
      "passed_with_waivers"
    } else if allPassed {
      "passed"
    } else {
      "incomplete"
    }
  }

  /// The plan's `known_gaps`: filtered of `prepared_not_performed` once the run
  /// was performed (which requires an array), and as declared before.
  private func knownGaps(plan: JSONValue?) throws(ShowcaseError) -> JSONValue {
    let declared = ShowcaseJavaScript.optionalMember(plan, "known_gaps")
    guard hasPerformedEvent else {
      return JavaScriptValue.isNullish(declared) ? .array([]) : declared ?? .array([])
    }
    var kept: [JSONValue] = []
    for gap in try ShowcaseJavaScript.arrayOrEmpty(declared, calling: "filter") {
      let code = try ShowcaseJavaScript.member(gap, "code")
      guard !ShowcaseJavaScript.isString(code, "prepared_not_performed") else {
        continue
      }
      kept.append(gap)
    }
    return .array(kept)
  }

  func status(
    runIdentifier: JSONValue?,
    isLedgerComplete: Bool,
    plan: JSONValue?,
  ) throws(ShowcaseError) -> ShowcaseRunStatus {
    let isApprovalStale = isOutcomeChangedAfterApproval
    return try ShowcaseRunStatus(
      runIdentifier: runIdentifier,
      isComplete: isLedgerComplete,
      executionStatus: isLedgerComplete ? executionStatus : "incomplete",
      runOutcome: isLedgerComplete ? runOutcome : "incomplete",
      approvalState: isApprovalStale ? "stale_due_to_run_change" : approvalState,
      unresolvedFailureCount: unresolvedFailures.count,
      approval: isApprovalStale ? nil : approval,
      items: items,
      knownGaps: knownGaps(plan: plan),
      ignoredApprovalEvents: ignoredApprovalEvents,
    )
  }
}
