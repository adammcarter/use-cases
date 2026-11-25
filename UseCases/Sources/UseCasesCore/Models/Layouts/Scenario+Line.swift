extension Scenario {
  /// The scenario in one line, `given G: W → T`: each part's sentences joined with `;` and
  /// without their full stops. A scenario with no `given` has none in the line; one with only a
  /// `when` or only a `then` shows that alone, and one with neither is told by its id.
  var line: String {
    let situation = Self.sentences(given)
    let action = Self.sentences(when)
    let outcome = Self.sentences(then)
    let steps: String = switch (action.isEmpty, outcome.isEmpty) {
    case (false, false):
      "\(action) → \(outcome)"
    case (false, true):
      action
    case (true, false):
      outcome
    case (true, true):
      identifier.text
    }

    return situation.isEmpty ? steps : "given \(situation): \(steps)"
  }

  private static func sentences(_ parts: [String]) -> String {
    parts.map { part in
      let text = part.withoutOuterWhitespace

      return text.hasSuffix(".") && !text.hasSuffix("..") ? String(text.dropLast()) : text
    }.joined(separator: "; ")
  }
}
