/// Something worth saying about the workspace as a whole in `status`, beside the use cases.
public enum WorkspaceWarning: Equatable, Sendable {
  /// A link, resource or store problem that does not make the workspace INVALID, as one line.
  case note(String)

  /// A run folder with no completion marker (chapter 12 §22). It is never evidence.
  case runNeverFinished(run: String)

  /// The warning as one line, with a run id in full, or shortened when a shortener is given.
  public func text(shortening: RunIdentifierShortener?) -> String {
    switch self {
    case let .note(text):
      text
    case let .runNeverFinished(run):
      "run \(RouteExplanation.shown(run, shortening: shortening)) never finished"
    }
  }
}
