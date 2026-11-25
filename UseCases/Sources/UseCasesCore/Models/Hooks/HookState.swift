/// What a hook is in this clone (chapter 18 §5). The raw value is the word the `--json` document
/// uses.
public enum HookState: String, Equatable, Sendable {
  /// The hook is exactly the one Use Cases writes for this workspace.
  case installed

  /// No hook file for that moment.
  case absent

  /// A different hook file is there; Use Cases leaves it alone.
  case other

  /// `core.hooksPath` is set; the hook manager owns every hook.
  case managed
}
