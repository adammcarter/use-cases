/// Computes the current fingerprint of every route of a loaded workspace (chapter 11 §2, §49).
public protocol RouteFingerprintComputing: Sendable {
  /// The fingerprint of every route of every READY use case of `workspace`, as the workspace is
  /// on disk now, or every problem that makes the workspace INVALID.
  ///
  /// Reads the files links point into and the files route resources name. A DRAFT use case has
  /// no fingerprint, though its resources are still checked (chapter 09 §20.2). When `links` is
  /// INVALID, its problems come back with the resource problems and no fingerprint is given:
  /// the link set would be unknown (chapter 11 §50). An explicit resource file in excluded
  /// content is allowed and warns; warnings never withhold a fingerprint.
  ///
  /// - Parameters:
  ///   - workspace: A workspace that loaded.
  ///   - links: What link resolution found in that workspace.
  /// - Returns: The fingerprints, or the problems and no fingerprints.
  func fingerprints(
    of workspace: LoadedWorkspace,
    links: LinkResolution,
  ) -> RouteFingerprints
}
