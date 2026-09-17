import UseCasesCore

/// One `selected_items` entry of a SAVED plan file, decoded the tolerant way
/// `plan cards` reads one.
///
/// `plan cards` is the only command that renders a plan it did not generate:
/// `loadPresentationPlanFile` checks `schema_version` and the content hash and
/// nothing else, so an older or hand-edited plan may be missing members the
/// core's ``PresentationPlanItem`` requires. The TypeScript `renderCard` reads
/// the item dynamically and so has two documented fallbacks (ladder note, row
/// 3f1):
///
/// - `presentation_format ?? defaultFormatForDeliveryKind(delivery_kind)`;
/// - `evidence_summary?.basis ?? "(earlier run)"`.
///
/// Where the TypeScript would instead read a property of `undefined`, it
/// raises a `TypeError` that `plan.cards` reports as `internal_error` with
/// V8's own wording. Those reads are format-specific — `Reviewing` never looks
/// at `resolved_steps`, `Explaining` looks at it only when there are no
/// expected observations — so this type checks them in the renderer's order
/// and raises the same message.
///
/// A `use_case_title` that is not a string is read as absent; the corpus has
/// no such plan, and the TypeScript's `?.trim()` would raise on a number.
struct PlanCardItem {
  /// V8's message for reading a property of `undefined`.
  static func undefinedRead(_ property: String) -> CommandFailure {
    CommandFailure(
      code: CommandFailure.internalErrorCode,
      message: "Cannot read properties of undefined (reading '\(property)')",
    )
  }

  /// The basis a `Reviewing` card cites when the plan holds none.
  static let earlierRun = "(earlier run)"

  let planItemIdentifier: String
  let useCaseIdentifier: String
  /// The item's own value, echoed into the card as read: absent stays absent.
  let recordedFormat: JSONValue?
  /// What the card is actually rendered as, fallback applied.
  let format: PresentationFormat
  let item: PresentationPlanItem

  init(_ value: JSONValue) throws(CommandFailure) {
    planItemIdentifier = value["plan_item_id"]?.stringValue ?? ""
    useCaseIdentifier = value["use_case_id"]?.stringValue ?? ""
    recordedFormat = value["presentation_format"]
    format = try Self.format(of: value)
    let steps = Self.strings(value["resolved_steps"])
    let observations = Self.strings(value["expected_observations"])
    try Self.checkReads(format: format, steps: steps, observations: observations)
    item = PresentationPlanItem(
      planItemIdentifier: planItemIdentifier,
      presentationFormat: format,
      deliveryKind: format.deliveryKind(base: .explanation),
      scenarioScope: .wholeUseCase,
      useCaseIdentifier: useCaseIdentifier,
      useCaseTitle: value["use_case_title"]?.stringValue,
      scenarioIdentifiers: [],
      useCaseContentHash: "",
      estimatedSeconds: 0,
      estimateSource: .defaultProfile,
      setupSteps: [],
      resolvedSteps: steps ?? [],
      expectedObservations: observations ?? [],
      teardownSteps: [],
      requiredPermissions: [],
      safetyConstraints: [],
      verificationPolicySnapshot: JSONObject(),
      approvalPolicySnapshot: JSONObject(),
      approvalResolutionRequiredAtRunStart: false,
      requiredEvidence: [],
      evidenceSummary: ItemEvidenceSummary(
        readiness: .unknown,
        activeEvidenceIdentifiers: [],
        basis: value["evidence_summary"]?["basis"]?.stringValue ?? Self.earlierRun,
      ),
      freshnessSummary: ItemFreshnessSummary(state: .unknown, basis: ""),
      knownGaps: [],
      selectionReasons: [],
      selectionReasonCodes: [],
      scoreComponents: ScoreComponents(changed: 0, value: nil, journey: nil, frequency: nil),
    )
  }

  /// `{ plan_item_id, use_case_id, presentation_format, text }`, with the
  /// format left out when the plan held none.
  func card(_ text: String) -> JSONValue {
    var object = JSONObject()
    object["plan_item_id"] = .string(planItemIdentifier)
    object["use_case_id"] = .string(useCaseIdentifier)
    object["presentation_format"] = recordedFormat
    object["text"] = .string(text)
    return .object(object)
  }

  /// The declared format, or the delivery kind's default. Anything the tables
  /// do not know reads as `undefined` in the TypeScript, whose next act is
  /// `FORMAT_META[format].emoji`.
  private static func format(of value: JSONValue) throws(CommandFailure) -> PresentationFormat {
    if let declared = value["presentation_format"] {
      guard let text = declared.stringValue, let format = PresentationFormat(rawValue: text) else {
        throw undefinedRead("emoji")
      }
      return format
    }
    guard let text = value["delivery_kind"]?.stringValue, let kind = DeliveryKind(rawValue: text)
    else {
      throw undefinedRead("emoji")
    }
    return PresentationFormat.defaultFormat(for: kind)
  }

  /// A JSON array of strings, or nil when the member is absent — which the
  /// TypeScript reads as `undefined`.
  private static func strings(_ value: JSONValue?) -> [String]? {
    guard let entries = value?.arrayValue else {
      return nil
    }
    return entries.compactMap(\.stringValue)
  }

  /// The properties the chosen format's body reads, in the order it reads
  /// them, so an absent array raises what the TypeScript raised.
  private static func checkReads(
    format: PresentationFormat,
    steps: [String]?,
    observations: [String]?,
  ) throws(CommandFailure) {
    switch format {
    case .testing:
      try require(steps, "length")
      try require(observations, "length")
    case .comparing:
      try require(steps, "0")
    case .inspecting:
      try require(steps, "0")
      try require(observations, "0")
    case .reviewing:
      try require(observations, "length")
    case .userLed:
      try require(steps, "length")
    case .explaining:
      try require(observations, "length")
      if observations?.isEmpty == true {
        try require(steps, "length")
      }
    }
  }

  private static func require(
    _ values: [String]?,
    _ property: String,
  ) throws(CommandFailure) {
    guard values == nil else {
      return
    }
    throw undefinedRead(property)
  }
}
