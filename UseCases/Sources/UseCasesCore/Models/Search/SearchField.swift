/// A part of a use case that `search --in` can name (chapter 16 §15).
public enum SearchField: String, CaseIterable, Sendable {
  case id
  case title
  case description
  case intent
  case scenarios
  case outOfScope = "out_of_scope"
  case validation

  /// How much a match in the field counts: the id and title most, then description and intent,
  /// then the rest.
  var weight: Int {
    switch self {
    case .id, .title:
      10
    case .description, .intent:
      6
    case .scenarios, .outOfScope, .validation:
      3
    }
  }
}
