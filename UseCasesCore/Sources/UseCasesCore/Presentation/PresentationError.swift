/// Why planning a presentation or rendering one of its cards stopped.
///
/// Rendering throws the TypeScript's `HonestyRuleError`s, each under its own
/// code: the header verb is a promise the body may not break. Planning throws
/// only what node lets escape while reading `use-cases.yml` for the workflow
/// snapshot.
public enum PresentationError: Error, Equatable, Sendable {
  /// A narrated format was handed a live pass or fail result. The verb names
  /// the format that refused it.
  case liveResultNotRenderable(verb: String)
  /// An "Over to you" card was answered by anything but a human.
  case userLedRequiresHumanAnswer
  /// A pass checkmark was claimed without an evidence id the item holds.
  case passRequiresRecordedEvidence
  /// Reading `use-cases.yml` failed; node's error escapes in the TypeScript.
  case fileAccess(FileAccessError)

  public var code: String {
    switch self {
    case .liveResultNotRenderable: "live_result_not_renderable"
    case .userLedRequiresHumanAnswer: "user_led_requires_human_answer"
    case .passRequiresRecordedEvidence: "pass_requires_recorded_evidence"
    case let .fileAccess(error): error.code
    }
  }

  public var message: String {
    switch self {
    case let .liveResultNotRenderable(verb):
      "A live result cannot be re-rendered under the \(verb) format."
    case .userLedRequiresHumanAnswer:
      "Over to you stays open until a human answers; an agent cannot fill it."
    case .passRequiresRecordedEvidence:
      "A pass checkmark requires a real recorded result, never agent prose alone."
    case let .fileAccess(error):
      error.message
    }
  }
}
