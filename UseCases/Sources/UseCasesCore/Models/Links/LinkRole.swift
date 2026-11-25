/// What a link is for (chapter 08 "Placement defines role"). There is no `role` field anywhere:
/// where a link is written decides it.
public enum LinkRole: String, Sendable {
  /// The code a use case is built in. Feeds freshness only.
  case implementation

  /// The code that proves a route. Each one expects a result when tests run.
  case validation
}
