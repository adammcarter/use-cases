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

  /// Results exist, none for the current fingerprint; this run has the newest.
  case changedSince(run: String)

  /// Nothing has been run for the route.
  case noVerdictYet

  /// The explanation as a sentence, with a run id in full or as its first 8 digits.
  public func text(shortRunIdentifiers: Bool) -> String {
    switch self {
    case let .decided(run, via):
      via.isEmpty
        ? "run \(Self.shown(run, short: shortRunIdentifiers))"
        : "run \(Self.shown(run, short: shortRunIdentifiers)) via \(via.joined(separator: ", "))"
    case let .withheld(problem, run):
      "\(problem) (run \(Self.shown(run, short: shortRunIdentifiers)))"
    case let .changedSince(run):
      "changed since run \(Self.shown(run, short: shortRunIdentifiers))"
    case .noVerdictYet:
      "no verdict yet"
    }
  }

  static func shown(
    _ run: String,
    short: Bool,
  ) -> String {
    short ? String(run.prefix(8)) : run
  }
}
