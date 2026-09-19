/// Ranking candidates (packages/core/src/presentation/scoring.ts).
enum PresentationScoring {
  /// `scoreUseCase`: changed first, then value tier, journey role (weighted per
  /// mode) and usage frequency.
  static func score(
    _ useCase: LoadedUseCase,
    mode: PresentationMode,
    isChanged: Bool,
  ) -> ScoreComponents {
    let journey = useCase.value["journey_role"]?.stringValue
    return ScoreComponents(
      changed: isChanged ? 1000 : 0,
      value: valueRank(useCase.value["value_tier"]?.stringValue),
      journey: mode == .showcase ? showcaseJourneyRank(journey) : walkthroughJourneyRank(journey),
      frequency: frequencyRank(useCase.value["usage_frequency"]?.stringValue),
    )
  }

  /// `compareCandidates`, as the sign `Array.prototype.sort` reads: each score
  /// descending, then feature id and use-case id by `localeCompare`. A rank
  /// the table does not know is `undefined` in the TypeScript; the difference
  /// is NaN, which the sort reads as "equal", so comparison stops there.
  static func compare(
    _ left: PresentationCandidate,
    _ right: PresentationCandidate,
  ) -> Int {
    let leftScores = left.scoreComponents
    let rightScores = right.scoreComponents
    let levels: [(Int?, Int?)] = [
      (leftScores.changed, rightScores.changed),
      (leftScores.value, rightScores.value),
      (leftScores.journey, rightScores.journey),
      (leftScores.frequency, rightScores.frequency),
    ]
    for (leftRank, rightRank) in levels {
      guard let leftRank, let rightRank else {
        return 0
      }
      if rightRank != leftRank {
        return rightRank - leftRank
      }
    }
    let featureOrder = localeCompare(
      left.useCase.feature["id"]?.stringValue ?? "",
      right.useCase.feature["id"]?.stringValue ?? "",
    )
    if featureOrder != 0 {
      return featureOrder
    }
    return localeCompare(left.useCase.identifier, right.useCase.identifier)
  }

  /// `candidates.slice().sort(compareCandidates)`: a stable sort, as V8's is.
  static func sorted(_ candidates: [PresentationCandidate]) -> [PresentationCandidate] {
    candidates.sorted { left, right in
      compare(left, right) < 0
    }
  }

  /// `left.localeCompare(right)` as -1, 0 or 1.
  static func localeCompare(
    _ left: String,
    _ right: String,
  ) -> Int {
    if JavaScriptStringOrder.localeAscending(left, right) {
      return -1
    }
    return JavaScriptStringOrder.localeAscending(right, left) ? 1 : 0
  }

  /// `scoreReasons`: a code and a sentence for each score.
  static func reasons(
    _ useCase: LoadedUseCase,
    isChanged: Bool,
    mode: PresentationMode,
  ) -> (codes: [String], reasons: [String]) {
    let tier = useCase.value["value_tier"]?.stringValue ?? ""
    let role = useCase.value["journey_role"]?.stringValue ?? ""
    let frequency = useCase.value["usage_frequency"]?.stringValue ?? ""
    var codes: [String] = []
    var reasons: [String] = []
    if isChanged {
      codes.append("changed_source")
      reasons.append("Matched an explicitly changed source path.")
    }
    codes.append("value_\(tier)")
    reasons.append("\(sentenceCase(tier)) value use case.")
    codes.append("journey_\(role)")
    reasons.append(
      mode == .showcase && role == "golden"
        ? "Golden path is preferred for a high-level showcase."
        : "\(sentenceCase(role)) journey coverage.",
    )
    codes.append("frequency_\(frequency)")
    reasons.append("\(sentenceCase(frequency)) usage frequency.")
    return (codes, reasons)
  }

  /// `sentenceCase`: underscores become spaces, and a leading `\w` is
  /// upper-cased.
  static func sentenceCase(_ value: String) -> String {
    let spaced = String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
      scalar == "_" ? " " : scalar
    }))
    guard let first = spaced.unicodeScalars.first, first.isASCII,
          first.properties.isAlphabetic || ("0" ... "9").contains(first) || first == "_"
    else {
      return spaced
    }
    return first.properties.uppercaseMapping + String(spaced.unicodeScalars.dropFirst())
  }

  private static func valueRank(_ tier: String?) -> Int? {
    switch tier {
    case "critical": 400
    case "core": 300
    case "supporting": 200
    case "long_tail": 100
    default: nil
    }
  }

  private static func showcaseJourneyRank(_ role: String?) -> Int? {
    switch role {
    case "golden": 50
    case "alternate": 40
    case "edge": 30
    case "negative": 20
    case "failure": 10
    default: nil
    }
  }

  private static func walkthroughJourneyRank(_ role: String?) -> Int? {
    switch role {
    case "golden": 50
    case "alternate", "edge", "negative", "failure": 45
    default: nil
    }
  }

  private static func frequencyRank(_ frequency: String?) -> Int? {
    switch frequency {
    case "common": 30
    case "occasional": 20
    case "rare": 10
    default: nil
    }
  }
}
