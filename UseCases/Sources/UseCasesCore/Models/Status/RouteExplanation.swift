/// Why a route has the status it has (chapter 15): the run that decided it, the run diagnostic
/// that withheld a verdict, or the run it has changed since. It keeps whole run ids; a person's
/// text shortens them.
public enum RouteExplanation: Equatable, Sendable {
  /// A result for the route's current fingerprint decided it. `via` names where the verdict came
  /// from: the validations whose reports gave it, or `record`.
  case decided(
    run: String,
    via: [String],
  )

  /// No result matches the current fingerprint, and the newest run that explains why says so.
  case withheld(
    problem: String,
    run: String,
  )

  /// No result matches the current fingerprint and the newest run that explains why says so, while
  /// older results exist: it also names the run holding the newest of them and what it said.
  case withheldSinceChange(
    problem: String,
    run: String,
    changedSince: String,
    lastResult: String,
  )

  /// Results exist, none for the current fingerprint; this run has the newest, and `lastResult`
  /// is what that result said.
  case changedSince(
    run: String,
    lastResult: String,
  )

  /// Nothing has been run for the route.
  case noVerdictYet

  /// The explanation as a sentence, with a run id in full, or shortened when a shortener is given.
  public func text(shortening: RunIdentifierShortener?) -> String {
    switch self {
    case let .decided(run, via):
      via.isEmpty
        ? "run \(Self.shown(run, shortening: shortening))"
        : "run \(Self.shown(run, shortening: shortening)) via \(via.joined(separator: ", "))"
    case let .withheld(problem, run):
      "\(problem) (run \(Self.shown(run, shortening: shortening)))"
    case let .withheldSinceChange(problem, run, changedSince, lastResult):
      "\(problem) (run \(Self.shown(run, shortening: shortening))) · changed since run "
        + "\(Self.shown(changedSince, shortening: shortening)) (last result: \(lastResult))"
    case let .changedSince(run, lastResult):
      "changed since run \(Self.shown(run, shortening: shortening)) (last result: \(lastResult))"
    case .noVerdictYet:
      "no verdict yet"
    }
  }

  static func shown(
    _ run: String,
    shortening: RunIdentifierShortener?,
  ) -> String {
    shortening?.shortened(run) ?? run
  }
}
