/// What `init` did about the `.use-cases/` line of `.gitignore` (chapter 17 §6, §8). The raw
/// value is the word the `--json` document uses.
public enum GitignoreOutcome: String, Equatable, Sendable {
  /// The line is written.
  case added

  /// A line already excludes `.use-cases/`.
  case present

  /// Nothing was written: no version control is there, or `.gitignore` cannot be edited.
  case skipped
}
