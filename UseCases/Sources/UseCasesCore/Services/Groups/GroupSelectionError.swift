/// Why a group cannot be named (chapter 16 §9).
public enum GroupSelectionError: Error, Equatable, Sendable {
  /// No group has this name. `known` are the names there are, in the order written.
  case unknown(name: String, known: [String])

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unknown(name, known):
      guard !known.isEmpty else {
        return "no group '\(name)': this workspace defines no groups (use-case-groups.yml)"
      }

      return "no group '\(name)' in use-case-groups.yml; the groups are "
        + known.joined(separator: ", ")
    }
  }
}
