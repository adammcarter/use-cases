/// A route's state and why, read from the store against the route's current fingerprint.
struct RouteJudgement: Equatable, Sendable {
  let status: VerificationStatus
  let explanation: RouteExplanation
}
