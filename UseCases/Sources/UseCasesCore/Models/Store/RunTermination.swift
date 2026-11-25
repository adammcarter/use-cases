/// How a sealed run ended (chapter 12 §20). It is never a route verdict.
enum RunTermination: String, CaseIterable, Sendable {
  case completed

  /// The request stopped before it completed: cancelled, or a started run closed by an abort.
  case interrupted
}
