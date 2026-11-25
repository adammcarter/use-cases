import UseCasesCore

extension HooksCommand {
  /// The words of the command line as an action and the hooks it names. `add` and `remove` need
  /// hooks to act on; listing takes none.
  func parsedWords() throws(HooksWordsError) -> (action: HookAction?, names: [HookName]) {
    // The first word is the action, so names without an action cannot come.
    guard let action else {
      return (nil, [])
    }

    guard let known = HookAction(rawValue: action) else {
      throw .unknownAction(action)
    }

    let hooks: [HookName]

    do {
      hooks = try HookName.named(names)
    } catch {
      throw .hook(error)
    }

    guard !hooks.isEmpty else {
      throw .noHooks(known)
    }

    return (known, hooks)
  }
}
