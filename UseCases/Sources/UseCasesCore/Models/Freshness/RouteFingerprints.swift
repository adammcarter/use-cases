/// What fingerprinting a loaded workspace found (chapter 11 §50, chapter 09 §20.2).
///
/// A fingerprint is authoritative only when nothing in the workspace is unresolved, so a result
/// with any problem holds no fingerprints.
public struct RouteFingerprints: Equatable, Sendable {
  /// The fingerprint of every route of every READY use case, in the order the workspace holds
  /// them: use cases as loaded, routes as written. Empty when ``isInvalid``.
  public let routes: [LiveRouteFingerprint]

  /// Every problem that makes the workspace INVALID, in report order (chapter 09 §27.1).
  let errors: [Diagnostic]

  /// Everything worth saying that does not make the workspace INVALID, in report order. A
  /// warning never withholds a fingerprint.
  let warnings: [Diagnostic]

  /// The SHA-256 of every file the fingerprints were computed from, sorted by path: the linked
  /// files and the resource files. Kept even when a problem withholds the fingerprints.
  let fileDigests: [FileDigest]

  private let byRoute: [Key: String]

  /// Whether a problem makes the workspace INVALID.
  public var isInvalid: Bool {
    !errors.isEmpty
  }

  /// Each problem on a line, `<file>:<line>: <message>` or `<file>: <message>`, in report order.
  public var problems: [String] {
    errors.map(\.description)
  }

  /// Each warning on a line in the same form, in report order.
  public var warningLines: [String] {
    warnings.map(\.description)
  }

  /// Keeps the fingerprints only when there is no problem.
  init(
    routes: [LiveRouteFingerprint],
    errors: [Diagnostic],
    warnings: [Diagnostic] = [],
    fileDigests: [FileDigest] = [],
  ) {
    let ordered = errors.inReportOrder
    let kept = ordered.isEmpty ? routes : []

    self.errors = ordered
    self.warnings = warnings.inReportOrder
    self.routes = kept
    self.fileDigests = fileDigests
    byRoute = Dictionary(
      kept.map { route in
        (Key(useCase: route.useCase, route: route.route), route.fingerprint)
      },
      uniquingKeysWith: { first, _ in
        first
      },
    )
  }

  /// The current fingerprint of a route; `nil` when the route has none: its use case is a
  /// DRAFT, it does not exist, or the workspace is INVALID.
  public func fingerprint(
    useCase: String,
    route: String,
  ) -> String? {
    byRoute[Key(useCase: useCase, route: route)]
  }

  private struct Key: Hashable, Sendable {
    let useCase: String
    let route: String
  }
}
