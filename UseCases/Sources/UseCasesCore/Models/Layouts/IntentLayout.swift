/// What the request is for (chapter 21 §7, step 2): the model `render intent` draws.
public struct IntentLayout: Equatable, Sendable {
  /// What is wanted.
  public let what: String

  /// Why it is wanted.
  public let why: String

  /// Who it is for; empty when the request does not say.
  public let who: [String]

  /// An intent.
  public init(
    what: String,
    why: String,
    who: [String],
  ) {
    self.what = what
    self.why = why
    self.who = who
  }
}
