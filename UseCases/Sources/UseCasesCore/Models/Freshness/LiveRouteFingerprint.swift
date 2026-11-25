/// The current fingerprint of one route of a READY use case (chapter 11 §2).
public struct LiveRouteFingerprint: Equatable, Sendable {
  /// The full id of the use case.
  public let useCase: String

  /// The route's id within the use case.
  public let route: String

  /// `uc-route-v1-sha256:` and 64 lowercase hexadecimal characters.
  public let fingerprint: String

  /// The files the fingerprint depends on: the use case's implementation links, the route's
  /// validation links and its resource files, each once, sorted by path.
  let files: [String]

  init(
    useCase: String,
    route: String,
    fingerprint: String,
    files: [String] = [],
  ) {
    self.useCase = useCase
    self.route = route
    self.fingerprint = fingerprint
    self.files = files
  }
}
