/// How much `init` sets up (chapter 17 §1).
public enum InitForm: Equatable, Sendable {
  /// The workspace, a worked example, a groups example and a commented bridge settings template.
  case full

  /// The workspace file alone.
  case minimal
}
