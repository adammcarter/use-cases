/// Why a hook name was refused.
public enum HookNameError: Error, Equatable, Sendable {
  /// These are not the name of a hook.
  case unknown(names: [String])

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unknown(names):
      "unknown hook \(names.joined(separator: ", ")); the hooks are "
        + HookName.allCases.map(\.rawValue).joined(separator: ", ")
    }
  }
}
