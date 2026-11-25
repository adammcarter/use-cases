import Foundation

/// One command to run and watch (chapter 14): a run command of `verify --run`, or a transformer
/// (chapter 10 §10).
struct ProcessRequest: Equatable, Sendable {
  /// The program and its arguments as stored, so `{report}` is still the literal token. The
  /// program is `arguments[0]`; no shell is involved (chapter 14 §6).
  let arguments: [String]

  /// The folder the command starts in: the validation's `working_dir`, or the workspace root
  /// (chapter 14 §8). A transformer starts in the workspace root.
  let workingDirectory: URL

  /// The absolute path `{report}` stands for (chapter 14 §5); `nil` when the command has no
  /// report token, as a transformer does not.
  let reportPath: String?

  /// How long the command may run, counted from a successful launch (chapter 14 §11).
  let timeout: Duration
}
