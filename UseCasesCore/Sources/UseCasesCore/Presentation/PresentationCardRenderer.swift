/// A live status a result may carry.
public enum RenderStatus: String, Sendable, Equatable {
  case pass
  case fail
}

/// A recorded outcome for an item, supplied at render time (`RenderResult`).
/// No result at all renders the open card; an empty result is still a result.
public struct RenderResult: Sendable, Equatable {
  /// Only Testing and Comparing may carry one.
  public let status: RenderStatus?
  /// What was actually observed.
  public let got: String?
  /// The recorded evidence backing a pass.
  public let evidenceIdentifier: String?
  /// True only when a human answered an "Over to you" prompt.
  public let answeredByHuman: Bool?

  public init(
    status: RenderStatus? = nil,
    got: String? = nil,
    evidenceIdentifier: String? = nil,
    answeredByHuman: Bool? = nil,
  ) {
    self.status = status
    self.got = got
    self.evidenceIdentifier = evidenceIdentifier
    self.answeredByHuman = answeredByHuman
  }
}

/// The fixed, scannable card for a plan item
/// (packages/core/src/presentation/renderCard.ts). Pure, and honest: the
/// header's emoji and verb are a promise the body may not break.
public enum PresentationCardRenderer {
  private static let passMark = "\u{2713}"
  private static let failMark = "\u{2717}"
  private static let middleDot = "\u{00B7}"

  /// `renderCard`: a markdown heading of emoji, verb and title (the id when
  /// the title is blank), the id and descriptor beneath, then the body.
  public static func renderCard(
    _ item: PresentationPlanItem,
    result: RenderResult? = nil,
  ) throws(PresentationError) -> String {
    let format = item.presentationFormat
    try enforceHonesty(item, format: format, result: result)
    let metadata = format.metadata
    let title = item.useCaseTitle.map(JavaScriptString.trim) ?? ""
    let heading = title.isEmpty ? item.useCaseIdentifier : title
    let header = "### \(metadata.emoji) \(metadata.verb): \(heading)\n\n"
      + "`\(item.useCaseIdentifier)` \(middleDot) \(metadata.descriptor)"
    return "\(header)\n\n\(body(item, format: format, result: result))"
  }

  private static func enforceHonesty(
    _ item: PresentationPlanItem,
    format: PresentationFormat,
    result: RenderResult?,
  ) throws(PresentationError) {
    guard let result else {
      return
    }
    let isLive = format == .testing || format == .comparing
    if !isLive, format != .userLed, result.status != nil {
      throw .liveResultNotRenderable(verb: format.metadata.verb)
    }
    if format == .userLed, result.answeredByHuman != true {
      throw .userLedRequiresHumanAnswer
    }
    if isLive, result.status == .pass {
      let evidenceIdentifier = result.evidenceIdentifier ?? ""
      let isBacked = !evidenceIdentifier.isEmpty
        && item.evidenceSummary.activeEvidenceIdentifiers.contains { active in
          PresentationPlanHelpers.sameCodeUnits(active, evidenceIdentifier)
        }
      if !isBacked {
        throw .passRequiresRecordedEvidence
      }
    }
  }

  private static func body(
    _ item: PresentationPlanItem,
    format: PresentationFormat,
    result: RenderResult?,
  ) -> String {
    switch format {
    case .testing: testing(item, result: result)
    case .comparing: comparing(item, result: result)
    case .inspecting: inspecting(item)
    case .reviewing: reviewing(item)
    case .userLed: userLed(item, result: result)
    case .explaining: explaining(item)
    }
  }

  private static func testing(
    _ item: PresentationPlanItem,
    result: RenderResult?,
  ) -> String {
    let steps = item.resolvedSteps.isEmpty
      ? ["1. (none)"]
      : numbered(item.resolvedSteps, separator: ". ")
    return (["**Steps**"] + steps + [
      "",
      "**Expect**",
      joined(item.expectedObservations),
      "",
      "**Actual**",
      gotLine(result),
    ]).joined(separator: "\n")
  }

  private static func comparing(
    _ item: PresentationPlanItem,
    result: RenderResult?,
  ) -> String {
    let blocked = item.resolvedSteps.first ?? "(blocked case)"
    let allowed = item.resolvedSteps.dropFirst().first ?? "(allowed case)"
    let got = result?.got ?? ""
    let suffix = got.isEmpty ? "" : "    -> \(got)"
    return [
      "\(failMark)  \(blocked)    -> should be blocked\(suffix)",
      "\(passMark)  \(allowed)    -> should work\(suffix)",
    ].joined(separator: "\n")
  }

  private static func inspecting(_ item: PresentationPlanItem) -> String {
    [
      "In:    \(item.resolvedSteps.first ?? "(the real artifact)")",
      "Look:  \(item.expectedObservations.first ?? "(the part that matters)")",
    ].joined(separator: "\n")
  }

  private static func reviewing(_ item: PresentationPlanItem) -> String {
    [
      "From:   \(item.evidenceSummary.basis)",
      "Shows:  \(joined(item.expectedObservations))    (not re-run now)",
    ].joined(separator: "\n")
  }

  private static func userLed(
    _ item: PresentationPlanItem,
    result: RenderResult?,
  ) -> String {
    let steps = item.resolvedSteps.isEmpty
      ? ["1.  (follow the steps with the agent)"]
      : numbered(item.resolvedSteps, separator: ".  ")
    let confirm = result?.answeredByHuman == true ? "Confirm:  yes" : "Confirm:  yes / no"
    return "\(steps.joined(separator: "\n"))\n\n\(confirm)"
  }

  private static func explaining(_ item: PresentationPlanItem) -> String {
    let text = item.expectedObservations.isEmpty
      ? joined(item.resolvedSteps)
      : joined(item.expectedObservations)
    return "\(text)\n\n(not run -- explanation only)"
  }

  /// `gotLine`: pending without a status, else what was seen and the mark,
  /// JavaScript-trimmed.
  private static func gotLine(_ result: RenderResult?) -> String {
    guard let status = result?.status else {
      return "(pending)"
    }
    let mark = status == .pass ? passMark : failMark
    return JavaScriptString.trim("\(result?.got ?? "") \(mark)")
  }

  private static func numbered(
    _ steps: [String],
    separator: String,
  ) -> [String] {
    steps.enumerated().map { index, step in
      "\(index + 1)\(separator)\(step)"
    }
  }

  private static func joined(_ values: [String]) -> String {
    values.isEmpty ? "(none)" : values.joined(separator: "; ")
  }
}
