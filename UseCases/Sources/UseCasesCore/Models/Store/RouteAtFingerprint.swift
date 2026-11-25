/// A route of a READY use case and its fingerprint as the workspace is now.
struct RouteAtFingerprint: Equatable, Sendable {
  let useCase: UseCaseIdentifier
  let route: RouteIdentifier
  let fingerprint: RouteFingerprint
}
