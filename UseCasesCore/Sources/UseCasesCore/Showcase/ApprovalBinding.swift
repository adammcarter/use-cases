/// The run facts an approval token must match, recomputed purely from the
/// live ledger (showcase/approvalBinding.ts).
public enum ApprovalBinding {
  /// `computeApprovalBindingFromEvents`: members in the TypeScript's order;
  /// `finish_event_id` is whatever the latest finish carries, and is left out
  /// when it carries none.
  public static func binding(
    runIdentifier: String,
    events: [JSONValue],
  ) throws(ShowcaseError) -> JSONObject {
    let ordered = try ShowcaseJavaScript.sortedBySequence(events)
    let start = try first(in: ordered, ofType: "run_started")
    guard let finish = try first(in: ordered.reversed(), ofType: "run_finished") else {
      throw .bindingRequiresFinish
    }
    let startPayload = ShowcaseJavaScript.optionalMember(start, "payload")
    let planContentHash = startFact(startPayload, "plan_content_hash", fallback: "")
    let gitCommit = startFact(startPayload, "git_commit", fallback: "unknown")

    let ledgerHeadHash = try ledgerHeadHash(runIdentifier: runIdentifier, ordered: ordered)
    let evidenceDigest = try evidenceDigest(runIdentifier: runIdentifier, ordered: ordered)
    let finishIdentifier = try ShowcaseJavaScript.member(finish, "event_id")
    let ciFreshnessDigest = try ciFreshnessDigest(
      startPayload: startPayload,
      planContentHash: planContentHash,
      finishIdentifier: finishIdentifier,
    )

    var binding = JSONObject()
    binding["run_id"] = .string(runIdentifier)
    binding["finish_event_id"] = finishIdentifier
    binding["plan_content_hash"] = .string(planContentHash)
    binding["ledger_head_hash"] = .string(ledgerHeadHash)
    binding["evidence_digest"] = .string(evidenceDigest)
    binding["git_commit"] = .string(gitCommit)
    binding["ci_freshness_digest"] = .string(ciFreshnessDigest)
    return binding
  }

  /// A hash over the whole ordered event-id chain.
  private static func ledgerHeadHash(
    runIdentifier: String,
    ordered: [JSONValue],
  ) throws(ShowcaseError) -> String {
    var eventIdentifiers: [JSONValue?] = []
    for event in ordered {
      try eventIdentifiers.append(ShowcaseJavaScript.member(event, "event_id"))
    }
    return try digest(
      JSONObject([("run_id", .string(runIdentifier))]),
      "event_ids",
      eventIdentifiers,
    )
  }

  /// A hash over the observation and verdict ids, bare-sorted.
  private static func evidenceDigest(
    runIdentifier: String,
    ordered: [JSONValue],
  ) throws(ShowcaseError) -> String {
    var evidenceIdentifiers: [JSONValue?] = []
    for event in ordered {
      let type = try ShowcaseJavaScript.member(event, "event_type")
      guard ShowcaseJavaScript.isString(type, "observation_recorded")
        || ShowcaseJavaScript.isString(type, "verdict_recorded")
      else {
        continue
      }
      try evidenceIdentifiers.append(ShowcaseJavaScript.member(event, "event_id"))
    }
    return try digest(
      JSONObject([("run_id", .string(runIdentifier))]),
      "evidence_event_ids",
      ShowcaseJavaScript.sortedAsStrings(evidenceIdentifiers),
    )
  }

  /// The start payload's non-empty `ci_freshness_digest` string, else a hash
  /// of the plan hash and the finish event id.
  private static func ciFreshnessDigest(
    startPayload: JSONValue?,
    planContentHash: String,
    finishIdentifier: JSONValue?,
  ) throws(ShowcaseError) -> String {
    let declared = ShowcaseJavaScript.optionalMember(startPayload, "ci_freshness_digest")
    if let freshness = declared?.stringValue, !freshness.isEmpty {
      return freshness
    }
    var facts = JSONObject([("plan_content_hash", .string(planContentHash))])
    facts["finish_event_id"] = finishIdentifier
    return try canonicalDigest(.object(facts))
  }

  /// `computeRunApprovalBinding`: read the live run, then bind it.
  public static func binding(
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
  ) throws(ShowcaseError) -> JSONObject {
    let read = try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier)
    return try binding(runIdentifier: runIdentifier, events: read.events)
  }

  /// `events.find((event) => event.event_type === type)`.
  static func first(
    in events: some Sequence<JSONValue>,
    ofType type: String,
  ) throws(ShowcaseError) -> JSONValue? {
    for event in events {
      guard try isType(event, type) else {
        continue
      }
      return event
    }
    return nil
  }

  static func isType(
    _ event: JSONValue,
    _ type: String,
  ) throws(ShowcaseError) -> Bool {
    try ShowcaseJavaScript.isString(ShowcaseJavaScript.member(event, "event_type"), type)
  }

  /// `String(start?.payload?.<key> ?? fallback)`.
  private static func startFact(
    _ payload: JSONValue?,
    _ key: String,
    fallback: String,
  ) -> String {
    let value = ShowcaseJavaScript.optionalMember(payload, key)
    return JavaScriptValue.isNullish(value) ? fallback : JavaScriptString.text(of: value)
  }

  /// `sha256(canonicalJson({ ...base, [key]: identifiers }))`. An absent
  /// identifier inside the array cannot be canonicalised, and throws.
  private static func digest(
    _ base: JSONObject,
    _ key: String,
    _ identifiers: [JSONValue?],
  ) throws(ShowcaseError) -> String {
    var elements: [JSONValue] = []
    for identifier in identifiers {
      guard let identifier else {
        throw .unsupportedCanonicalValue
      }
      elements.append(identifier)
    }
    var object = base
    object[key] = .array(elements)
    return try canonicalDigest(.object(object))
  }

  static func canonicalDigest(_ value: JSONValue) throws(ShowcaseError) -> String {
    do throws(CodeUnitCanonicalJSONError) {
      return try CodeUnitCanonicalJSON.sha256(value)
    } catch {
      throw .unsupportedCanonicalValue
    }
  }
}

/// A plan's content hash checked against its body (showcase/planBinding.ts).
public enum PlanBinding {
  /// `PLACEHOLDER_HASH`.
  public static let placeholderHash = PresentationPlanner.zeroHash

  /// `loadPresentationPlanFile`: read and parse the file, require a version 1
  /// plan with a string hash, then check the hash.
  public static func loadPlanFile(atPath path: String) throws(ShowcaseError) -> JSONObject {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      throw .planFileUnreadable(detail: error.message)
    }
    let value: JSONValue
    do throws(SchemaError) {
      value = try JSONParser.parse(text)
    } catch {
      throw .planFileUnreadable(detail: error.message)
    }
    guard let plan = JavaScriptPropertyOrder.reordered(value).objectValue,
          plan["schema_version"] == .number(1),
          plan["plan_content_hash"]?.stringValue != nil
    else {
      throw .planFileInvalid
    }
    try assertPlanHash(plan)
    return plan
  }

  /// `assertPresentationPlanHash`.
  public static func assertPlanHash(_ plan: JSONObject) throws(ShowcaseError) {
    if ShowcaseJavaScript.isString(plan["plan_content_hash"], placeholderHash) {
      throw .planPlaceholderHash
    }
    guard ShowcaseJavaScript.isString(
      plan["plan_content_hash"],
      PresentationPlanner.planContentHash(of: plan),
    ) else {
      throw .planHashMismatch
    }
  }
}
