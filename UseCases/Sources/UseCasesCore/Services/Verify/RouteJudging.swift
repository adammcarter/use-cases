/// Judges routes from the results of every source (chapter 07 "How the core judges", chapter 13
/// §9). Only the core judges: a transformer reports what happened to each link, never a verdict.
protocol RouteJudging: Sendable {
  /// What each route came to.
  ///
  /// Results from every source merge first: several results for one link are one, the worst
  /// winning. Then each route is judged once:
  ///
  /// - a route with no validation link and no procedure has no verdict (`notLinked`);
  /// - a link with no result and no failure anywhere in the route: no verdict (`didntRun`);
  /// - a failed link makes the route `fail` even when another link did not run;
  /// - otherwise the worst of the results wins: `fail`, `error`, `incomplete`, `pass`.
  ///
  /// A route with a procedure and no validation link has no outcome: only `record` can speak for
  /// it.
  ///
  /// - Parameters:
  ///   - routes: The routes to judge.
  ///   - sources: What reading each source gave, in the order of the bridge settings. A source
  ///     with a run error has no results.
  func judge(
    _ routes: [JudgedRoute],
    from sources: [SourceOutcome],
  ) -> [RouteKey: RouteOutcome]
}
