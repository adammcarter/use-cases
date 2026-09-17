/// Starts showcase runs and appends their events
/// (packages/core/src/showcase/appendShowcaseEvent.ts).
///
/// Every append reads the run's ledger, refuses a damaged one, returns the
/// earlier event for a repeated idempotency key with the same intent (and
/// refuses one with a different intent), numbers the new event
/// `events.length + 1`, names it `evt.<run id>.<sequence>`, and appends it.
///
/// No lock is taken and nothing in this process serialises appends: two
/// appends to one run that read the same ledger both write the same sequence
/// and event id, exactly as two TypeScript processes do. That race is a
/// recorded owner decision (docs/rewrite/ladder-notes.md), not a porting gap.
public struct ShowcaseRecorder: Sendable {
  let clock: any ShowcaseClock

  public init(clock: any ShowcaseClock = SystemShowcaseClock()) {
    self.clock = clock
  }

  // MARK: - Start

  /// `startShowcaseRun`.
  public func start(
    plan: JSONObject,
    controlMode: ShowcaseControlMode,
    knownGapAcknowledgement: ShowcaseKnownGapAcknowledgement? = nil,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try PlanBinding.assertPlanHash(plan)
    if JavaScriptValue.isTruthy(plan["integrity_acknowledgement_required"]),
       knownGapAcknowledgement == nil
    {
      throw .knownGapAcknowledgementRequired
    }
    let runIdentifier = runIdentifier(recording)
    let payload = JSONObject([
      ("plan", .object(plan)),
      ("plan_content_hash", plan["plan_content_hash"] ?? .null),
      ("control_mode", .string(controlMode.rawValue)),
      ("initial_epoch_id", .string("epoch.1")),
      ("known_gap_acknowledgement", knownGapAcknowledgement?.jsonValue ?? .null),
    ])
    let context = recording.context
    let existing = try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier)
    let ledgerPath = ShowcaseLedger.ledgerPath(context: context, runIdentifier: runIdentifier)
    if !existing.isComplete, NodeFile.exists(atPath: ledgerPath) {
      throw .startAgainstDamagedLedger
    }
    let existingEvent = try Self.event(in: existing.events, keyedBy: recording.idempotencyKey)
    let digest = Self.intentDigest("run_started", payload, recording)
    if let existingEvent {
      guard try ShowcaseJavaScript.isString(
        ShowcaseJavaScript.member(existingEvent, "intent_digest"),
        digest,
      ) else {
        throw .idempotencyConflict
      }
      return try appendResult(context: context, event: existingEvent)
    }
    guard existing.events.isEmpty else {
      throw .runIdentifierConflict
    }
    let event = makeEvent(
      runIdentifier: runIdentifier,
      eventType: "run_started",
      sequence: 1,
      payload: payload,
      recording: recording,
    )
    try ShowcaseLedger.appendLine(context: context, runIdentifier: runIdentifier, event: event)
    return try appendResult(context: context, event: event)
  }

  // MARK: - Events

  /// `appendShowcaseObservation`. The text is redacted before anything else
  /// sees it, so the ledger never holds the secret and the intent digest is
  /// taken over the stored form.
  public func recordObservation(
    runIdentifier: String,
    planItemIdentifier: String,
    text: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appended(runIdentifier, "observation_recorded", recording, [
      ("plan_item_id", .string(planItemIdentifier)),
      ("epoch_id", .string("epoch.1")),
      ("observation", .string(Redactor.redactSecrets(text))),
    ])
  }

  /// `appendShowcaseAction`. The action is recorded as given, unredacted.
  public func recordAction(
    runIdentifier: String,
    planItemIdentifier: String,
    action: JSONObject,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appended(runIdentifier, "action_recorded", recording, [
      ("plan_item_id", .string(planItemIdentifier)),
      ("epoch_id", .string("epoch.1")),
      ("action", .object(action)),
    ])
  }

  /// `appendShowcaseVerdict`: at least one named event must be an observation
  /// of the same item.
  public func recordVerdict(
    runIdentifier: String,
    planItemIdentifier: String,
    verdict: ShowcaseVerdict,
    observationEventIdentifiers: [String],
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let read = try ShowcaseLedger.read(context: recording.context, runIdentifier: runIdentifier)
    var observations = JavaScriptValueSet()
    for event in read.events {
      guard try ApprovalBinding.isType(event, "observation_recorded") else {
        continue
      }
      let item = try ShowcaseJavaScript.member(
        ShowcaseJavaScript.member(event, "payload"),
        "plan_item_id",
      )
      if ShowcaseJavaScript.isString(item, planItemIdentifier) {
        try observations.insert(ShowcaseJavaScript.member(event, "event_id"))
      }
    }
    let isObserved = observationEventIdentifiers.contains { identifier in
      observations.contains(.string(identifier))
    }
    guard isObserved else {
      throw .verdictRequiresObservation
    }
    return try appended(runIdentifier, "verdict_recorded", recording, [
      ("plan_item_id", .string(planItemIdentifier)),
      ("epoch_id", .string("epoch.1")),
      ("observation_event_ids", .array(observationEventIdentifiers.map(JSONValue.string))),
      ("verdict", .string(verdict.rawValue)),
      ("verifier", .object(JSONObject([("type", .string(recording.actorType.rawValue))]))),
    ])
  }

  /// `appendShowcaseFailureDecision`: the target must be a verdict, recorded
  /// or corrected, whose verdict is `fail` or `blocked`.
  public func recordFailureDecision(
    runIdentifier: String,
    verdictEventIdentifier: String,
    decision: ShowcaseFailureDecision,
    reason: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let read = try ShowcaseLedger.read(context: recording.context, runIdentifier: runIdentifier)
    guard let target = try Self.event(in: read.events, identifiedBy: verdictEventIdentifier) else {
      throw .failureDecisionTargetNotVerdict
    }
    let targetType = try ShowcaseJavaScript.member(target, "event_type")
    let isRecorded = ShowcaseJavaScript.isString(targetType, "verdict_recorded")
    guard isRecorded || ShowcaseJavaScript.isString(targetType, "verdict_corrected") else {
      throw .failureDecisionTargetNotVerdict
    }
    let targetVerdict = try ShowcaseJavaScript.member(
      ShowcaseJavaScript.member(target, "payload"),
      isRecorded ? "verdict" : "corrected_verdict",
    )
    guard ShowcaseJavaScript.isString(targetVerdict, "fail")
      || ShowcaseJavaScript.isString(targetVerdict, "blocked")
    else {
      throw .failureDecisionTargetNotFailure
    }
    return try appended(runIdentifier, "failure_decision_recorded", recording, [
      ("verdict_event_id", .string(verdictEventIdentifier)),
      ("decision", .string(decision.rawValue)),
      ("reason", .string(reason)),
    ])
  }

  /// `pauseShowcaseRun`. The reason is not redacted.
  public func pause(
    runIdentifier: String,
    reason: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appended(runIdentifier, "run_paused", recording, [("reason", .string(reason))])
  }

  /// `resumeShowcaseRun`.
  public func resume(
    runIdentifier: String,
    reason: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appended(runIdentifier, "run_resumed", recording, [("reason", .string(reason))])
  }

  /// `appendShowcaseEpoch`. The epoch ids are the literals `epoch.1` and
  /// `epoch.2` on every call: a second epoch is `epoch.2` again, never
  /// `epoch.3`, and later observations still say `epoch.1`.
  public func startEpoch(
    runIdentifier: String,
    reason: ShowcaseEpochReason,
    staleItemIdentifiers: [String],
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appended(runIdentifier, "epoch_started", recording, [
      ("previous_epoch_id", .string("epoch.1")),
      ("epoch_id", .string("epoch.2")),
      ("reason", .string(reason.rawValue)),
      ("stale_item_ids", .array(staleItemIdentifiers.map(JSONValue.string))),
      ("staling_strategy", .string("all_prior_verdicts")),
    ])
  }

  /// `finishShowcaseRun`: refused while any failed or blocked verdict lacks a
  /// failure decision.
  public func finish(
    runIdentifier: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let status = try ShowcaseReplay.replay(context: recording.context, runIdentifier: runIdentifier)
    guard status.unresolvedFailureCount == 0 else {
      throw .failureDecisionRequired
    }
    return try appended(
      runIdentifier,
      "run_finished",
      recording,
      [("requested_finish", .bool(true))],
    )
  }

  /// `correctShowcaseVerdict`: the target must be a recorded (not corrected)
  /// verdict.
  public func correctVerdict(
    runIdentifier: String,
    targetEventIdentifier: String,
    correctedVerdict: ShowcaseVerdict,
    reason: String,
    recording: ShowcaseRecording,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let read = try ShowcaseLedger.read(context: recording.context, runIdentifier: runIdentifier)
    guard let target = try Self.event(in: read.events, identifiedBy: targetEventIdentifier),
          try ApprovalBinding.isType(target, "verdict_recorded")
    else {
      throw .invalidCorrectionTarget
    }
    var payload = JSONObject([("target_event_id", .string(targetEventIdentifier))])
    payload["plan_item_id"] = try ShowcaseJavaScript.member(
      ShowcaseJavaScript.member(target, "payload"),
      "plan_item_id",
    )
    payload["corrected_verdict"] = .string(correctedVerdict.rawValue)
    payload["reason"] = .string(reason)
    return try appendResult(
      context: recording.context,
      event: appendEvent(runIdentifier, "verdict_corrected", recording, payload),
    )
  }

  // MARK: - Shared

  private func appended(
    _ runIdentifier: String,
    _ eventType: String,
    _ recording: ShowcaseRecording,
    _ payload: [(String, JSONValue)],
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try appendResult(
      context: recording.context,
      event: appendEvent(runIdentifier, eventType, recording, JSONObject(payload)),
    )
  }
}
