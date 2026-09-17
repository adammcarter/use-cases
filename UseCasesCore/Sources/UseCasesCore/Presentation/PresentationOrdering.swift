/// Putting eligible candidates in order and taking what fits
/// (packages/core/src/presentation/ordering.ts and selection.ts).
enum PresentationOrdering {
  /// `orderWalkthrough`: a golden critical or core item first, then the first
  /// alternate, edge, negative and failure item, then the rest — each pick in
  /// comparator order.
  static func walkthrough(_ candidates: [PresentationCandidate]) -> [PresentationCandidate] {
    let sorted = PresentationScoring.sorted(candidates)
    var ordered: [PresentationCandidate] = []
    var used = Set<CodeUnitKey>()

    func takeFirst(where predicate: (PresentationCandidate) -> Bool) {
      let match = sorted.first { candidate in
        !used.contains(CodeUnitKey(candidate.useCase.identifier)) && predicate(candidate)
      }
      if let match {
        used.insert(CodeUnitKey(match.useCase.identifier))
        ordered.append(match)
      }
    }

    takeFirst { candidate in
      let tier = candidate.useCase.value["value_tier"]?.stringValue
      return candidate.useCase.value["journey_role"]?.stringValue == "golden"
        && (tier == "critical" || tier == "core")
    }
    for role in ["alternate", "edge", "negative", "failure"] {
      takeFirst { candidate in
        candidate.useCase.value["journey_role"]?.stringValue == role
      }
    }
    for candidate in sorted where used.insert(CodeUnitKey(candidate.useCase.identifier)).inserted {
      ordered.append(candidate)
    }
    return ordered
  }

  /// `selectWithinLimits`: take items in order until the item cap or the
  /// timebox, at a flat estimate per item, would be passed. Comparisons are
  /// JavaScript's on doubles, so a NaN cap never stops the walk.
  static func withinLimits(
    _ ordered: [PresentationCandidate],
    estimatedSeconds: Double,
    maxItems: Double,
    timeboxSeconds: Double,
  ) -> [PresentationCandidate] {
    var selected: [PresentationCandidate] = []
    var usedSeconds = 0.0
    for candidate in ordered {
      if Double(selected.count) >= maxItems {
        break
      }
      if usedSeconds + estimatedSeconds > timeboxSeconds {
        break
      }
      selected.append(candidate)
      usedSeconds += estimatedSeconds
    }
    return selected
  }
}
