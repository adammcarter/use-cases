/// What a `save` or `remove` did to one use case (chapter 16 §14).
public enum UseCaseChangeAction: String, Equatable, Sendable {
  /// The use case is the first of a new definition file.
  case created

  /// The use case joined the file that already holds its group.
  case added

  /// The use case was already there, and was rewritten whole.
  case replaced

  /// The use case was already there, exactly as sent: nothing is written.
  case unchanged

  /// The use case was taken out.
  case removed
}
