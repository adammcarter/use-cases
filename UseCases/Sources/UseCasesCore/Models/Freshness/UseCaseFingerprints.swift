/// The routes of one use case that could be fingerprinted, and every problem met.
struct UseCaseFingerprints: Equatable, Sendable {
  var routes: [LiveRouteFingerprint] = []
  var diagnostics: [Diagnostic] = []
}
