/// A reason a route received no verdict in a run, or a link warning (chapter 12 §11).
/// Diagnostics explain; they never count as results.
struct RunDiagnostic: Equatable, Sendable {
  let problem: String
  let useCase: UseCaseIdentifier?
  let route: RouteIdentifier?

  /// The route fingerprint at the start point.
  let fingerprint: RouteFingerprint?

  /// What changed since the start point, for "code changed during the run".
  let files: [WorkspacePath]

  /// The link keys that got no result, for "its test didn't run".
  let links: [String]
}
