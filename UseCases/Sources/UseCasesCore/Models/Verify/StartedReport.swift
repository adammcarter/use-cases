/// The `{report}` of one validation in a started run: the absolute path its tests write to
/// (chapter 10 §8).
public struct StartedReport: Equatable, Sendable {
  /// The validation's id.
  public let validation: String

  /// An absolute path: a file inside the validation's reports folder, or the folder itself.
  public let path: String

  /// Makes a report.
  public init(
    validation: String,
    path: String,
  ) {
    self.validation = validation
    self.path = path
  }
}
