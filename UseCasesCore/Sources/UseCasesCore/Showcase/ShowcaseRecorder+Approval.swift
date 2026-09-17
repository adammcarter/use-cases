/// A user or agent's approval or rejection, with the signed token and keyring
/// resolvers that make a user's decision trusted (`ApprovalVerificationOptions`).
public struct ShowcaseApprovalRequest: Sendable {
  public let runIdentifier: String
  public let statement: String
  /// The signed token as parsed; only a truthy value counts as supplied.
  public let approvalToken: JSONValue?
  public let resolvers: ShowcaseTrustResolvers
  /// The instant a token's expiry is checked at; the clock's when nil.
  public let nowMilliseconds: Double?
  public let recording: ShowcaseRecording

  public init(
    runIdentifier: String,
    statement: String,
    approvalToken: JSONValue? = nil,
    resolvers: ShowcaseTrustResolvers = .none,
    nowMilliseconds: Double? = nil,
    recording: ShowcaseRecording,
  ) {
    self.runIdentifier = runIdentifier
    self.statement = statement
    self.approvalToken = approvalToken
    self.resolvers = resolvers
    self.nowMilliseconds = nowMilliseconds
    self.recording = recording
  }
}

/// How a decision was captured: the capture method, and — for a verified
/// token — the token, its decision and its tier.
private struct DecisionCapture {
  let method: String
  let token: JSONValue?
  let decision: String
  let assuranceTier: AssuranceTier?
}

extension ShowcaseRecorder {
  /// `appendShowcaseApproval`.
  public func approve(
    _ request: ShowcaseApprovalRequest,
    decision: ShowcaseApprovalDecision,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    try recordDecision(request, eventType: "approval_recorded", decision: decision.rawValue)
  }

  /// `rejectShowcaseApproval`.
  public func reject(_ request: ShowcaseApprovalRequest) throws(ShowcaseError)
    -> ShowcaseAppendResult
  {
    try recordDecision(request, eventType: "approval_rejected", decision: "rejected")
  }

  /// `recordApprovalDecision`, the one gate both flow through. In order: a
  /// repeated idempotency key returns the earlier event without verifying
  /// anything; a non-user actor may not decide a user-approval plan; a finish
  /// must exist; a user's token — when one is supplied — must not reuse a
  /// burned nonce, must verify against the live binding and the plan's floor,
  /// and must carry the decision being recorded, and its nonce is burned in
  /// its own event before the decision is appended; a user-approval plan
  /// without a token is refused.
  private func recordDecision(
    _ request: ShowcaseApprovalRequest,
    eventType: String,
    decision: String,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let recording = request.recording
    let context = recording.context
    let read = try ShowcaseLedger.read(context: context, runIdentifier: request.runIdentifier)

    if let existing = try Self.event(in: read.events, keyedBy: recording.idempotencyKey) {
      return try appendResult(context: context, event: existing)
    }

    let start = try ApprovalBinding.first(in: read.events, ofType: "run_started")
    let plan: JSONValue? = if let start {
      try ShowcaseJavaScript.member(ShowcaseJavaScript.member(start, "payload"), "plan")
    } else {
      nil
    }
    let isUserRequired = try ApprovalPolicy.requiresUserApproval(plan: plan)
    let assuranceFloor = try ApprovalPolicy.assuranceFloor(forPlan: plan)
    if recording.actorType != .user, isUserRequired {
      throw .userRequiredApproval
    }
    guard let finish = try ApprovalBinding.first(
      in: read.events.reversed(),
      ofType: "run_finished",
    ) else {
      throw .finishRequiredForApproval
    }
    let status = try ShowcaseReplay.replay(context: context, runIdentifier: request.runIdentifier)
    let capture = try capturedDecision(
      request,
      eventType: eventType,
      decision: decision,
      events: read.events,
      policy: (isUserRequired, assuranceFloor),
    )

    let payload = try Self.decisionPayload(
      request,
      eventType: eventType,
      capture: capture,
      scope: Self.scope(plan: plan, finish: finish, status: status),
    )
    let event = try appendEvent(request.runIdentifier, eventType, recording, payload)
    return try appendResult(context: context, event: event, trust: request.resolvers)
  }

  /// A user's supplied token is verified, its decision matched to the event,
  /// and its nonce burned; a user-approval plan without one is refused. Any
  /// other decision is captured as the caller's word.
  private func capturedDecision(
    _ request: ShowcaseApprovalRequest,
    eventType: String,
    decision: String,
    events: [JSONValue],
    policy: (isUserRequired: Bool, floor: AssuranceTier),
  ) throws(ShowcaseError) -> DecisionCapture {
    let recording = request.recording
    let isUser = recording.actorType == .user
    let capture = DecisionCapture(
      method: isUser ? "same_channel_operator_confirmation" : "command_handler",
      token: nil,
      decision: decision,
      assuranceTier: nil,
    )
    guard isUser else {
      return capture
    }
    guard JavaScriptValue.isTruthy(request.approvalToken), let token = request.approvalToken else {
      if policy.isUserRequired {
        throw .trustedUserConfirmationRequired
      }
      return capture
    }
    let verified = try verifiedToken(token, request, events: events, floor: policy.floor)
    let isRejection = JavaScriptString.identical(verified.decision, "rejected")
    if eventType == "approval_recorded", isRejection {
      throw .approvalDecisionMismatch(detail: "rejected token cannot record approval")
    }
    if eventType == "approval_rejected", !isRejection {
      throw .approvalDecisionMismatch(detail: "approval token cannot record rejection")
    }
    _ = try appendEvent(
      request.runIdentifier,
      "approval_nonce_burned",
      ShowcaseRecording(
        context: recording.context,
        actorType: recording.actorType,
        hostSurface: recording.hostSurface,
        idempotencyKey: "\(recording.idempotencyKey):nonce-burn",
        recordedAt: recording.recordedAt,
      ),
      JSONObject([
        ("jti", .string(verified.jti)),
        ("key_id", .string(verified.keyIdentifier)),
        ("run_id", .string(request.runIdentifier)),
      ]),
    )
    return DecisionCapture(
      method: "host_signed_approval_token",
      token: token,
      decision: verified.decision,
      assuranceTier: verified.assuranceTier,
    )
  }

  /// `{ plan_content_hash, finish_event_id, run_outcome, known_gap_count }`.
  private static func scope(
    plan: JSONValue?,
    finish: JSONValue,
    status: ShowcaseRunStatus,
  ) throws(ShowcaseError) -> JSONObject {
    var scope = JSONObject()
    let planHash = ShowcaseJavaScript.optionalMember(plan, "plan_content_hash")
    scope["plan_content_hash"] = JavaScriptValue.isNullish(planHash) ? .string("") : planHash
    scope["finish_event_id"] = try ShowcaseJavaScript.member(finish, "event_id")
    scope["run_outcome"] = .string(status.runOutcome)
    scope["known_gap_count"] = ShowcaseJavaScript.length(of: status.knownGaps)
    return scope
  }

  /// The decision event's payload, in the TypeScript's member order, with the
  /// token last when one was verified.
  private static func decisionPayload(
    _ request: ShowcaseApprovalRequest,
    eventType: String,
    capture: DecisionCapture,
    scope: JSONObject,
  ) -> JSONObject {
    let actorType = request.recording.actorType.rawValue
    var approver = JSONObject([("type", .string(actorType))])
    if let tier = capture.assuranceTier {
      approver["actor_type"] = .string(actorType)
      approver["assurance_tier"] = .string(tier.rawValue)
    }
    let statementKey = eventType == "approval_recorded"
      ? "approval_statement" : "rejection_statement"
    var payload = JSONObject([
      ("decision", .string(capture.decision)),
      ("approver", .object(approver)),
      ("capture_method", .string(capture.method)),
      (statementKey, .string(request.statement)),
      ("scope", .object(scope)),
    ])
    payload["approval_token"] = capture.token
    return payload
  }

  /// The verified facts of a supplied token: burned nonces refused first, then
  /// `verifyApprovalToken` against the live binding recomputed from the read.
  private func verifiedToken(
    _ token: JSONValue,
    _ request: ShowcaseApprovalRequest,
    events: [JSONValue],
    floor: AssuranceTier,
  ) throws(ShowcaseError) -> TrustedUserDecision {
    let liveBinding = try ApprovalBinding.binding(
      runIdentifier: request.runIdentifier,
      events: events,
    )
    let burned = try Self.burnedNonces(events)
    if let jti = token["jti"]?.stringValue, burned.contains(CodeUnitKey(jti)) {
      throw .approvalTokenRejected(
        failure: .nonceBurned,
        detail: "approval token nonce already burned (replay)",
      )
    }
    let options = ApprovalTokenVerificationOptions(
      token: token,
      resolvers: request.resolvers,
      liveBinding: .object(liveBinding),
      isNonceBurned: { jti in
        burned.contains(CodeUnitKey(jti))
      },
      nowMilliseconds: request.nowMilliseconds,
      assuranceFloor: floor,
    )
    switch ApprovalTokenVerifier.verify(options, clock: clock) {
    case let .failed(code, message):
      throw .approvalTokenRejected(failure: code, detail: message)
    case let .verified(jti, decision, keyIdentifier, assuranceTier):
      return TrustedUserDecision(
        jti: jti,
        actorType: .string(request.recording.actorType.rawValue),
        assuranceTier: assuranceTier,
        decision: decision,
        keyIdentifier: keyIdentifier,
      )
    }
  }

  /// `burnedNonceSet`: every string `jti` in an `approval_nonce_burned` payload.
  private static func burnedNonces(_ events: [JSONValue]) throws(ShowcaseError)
    -> Set<CodeUnitKey>
  {
    var burned = Set<CodeUnitKey>()
    for event in events {
      guard try ApprovalBinding.isType(event, "approval_nonce_burned") else {
        continue
      }
      let payload = try ShowcaseJavaScript.member(event, "payload")
      if let jti = try ShowcaseJavaScript.member(payload, "jti")?.stringValue {
        burned.insert(CodeUnitKey(jti))
      }
    }
    return burned
  }
}
