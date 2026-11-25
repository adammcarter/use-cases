import UseCasesCore

/// Why the words after `hooks` could not be read.
enum HooksWordsError: Error, Equatable {
  /// The first word is neither `add` nor `remove`.
  case unknownAction(String)

  /// An action with no hook to act on.
  case noHooks(HookAction)

  /// A word that is not a hook.
  case hook(HookNameError)

  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case let .unknownAction(word):
      "unknown action '\(word)': use add or remove, or no word to list the hooks"
    case let .noHooks(action):
      "say which hooks to \(action.rawValue): "
        + HookName.allCases.map(\.rawValue).joined(separator: ", ")
    case let .hook(error):
      error.message
    }
  }
}
