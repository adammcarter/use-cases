/// Something worth saying about one use case in `status` (chapter 08, chapter 16 §9).
public struct UseCaseWarning: Equatable, Sendable {
  /// What the warning is about.
  public enum Kind: Equatable, Sendable {
    /// A marked region holds no code, which usually means the code moved.
    case markedRegionEmpty

    /// Freshness will not track the use case's code.
    case noImplementationLinks

    /// A gating route has nothing a test report or a person can reach.
    case routeNotLinked
  }

  public let kind: Kind

  /// The warning as one line, such as `src/pay.py:2: its marked region is empty; if the code
  /// moved, move its markers with it`.
  public let text: String

  /// Whether the warning is worth a line in the list of use cases, and not only in the detail of
  /// one. A use case with no links is the normal case before any code exists.
  public var isListed: Bool {
    kind == .markedRegionEmpty
  }
}
