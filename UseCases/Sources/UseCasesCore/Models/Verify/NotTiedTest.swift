/// A test that ran but sits inside no link, as a person is told about it (chapter 15 §6).
public struct NotTiedTest: Equatable, Sendable {
  /// The test's name as its transformer reported it.
  public let name: String

  /// Where the test is, when the transformer knew.
  public let file: String?
  public let line: Int?

  /// How the test ended: `pass`, `fail`, `incomplete` or `error`.
  public let status: String
}
