/// What a plan does to one file (chapter 16 §17).
public enum FileChangeAction: String, Equatable, Sendable {
  /// The file is not there yet and is made. Something already there is an error: a plan never
  /// overwrites what it did not plan to replace.
  case create

  /// The file is there and is replaced whole.
  case replace

  /// The file is there and is removed.
  case delete
}
