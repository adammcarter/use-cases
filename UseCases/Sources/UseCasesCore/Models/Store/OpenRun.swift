import Foundation

/// A run that has been allocated and published but not sealed (chapter 12 §6): its folder holds
/// the initial manifest and an empty log, and results can be appended until it is sealed.
struct OpenRun: Equatable, Sendable {
  /// The workspace root the run's store sits in.
  let workspace: URL

  /// The manifest as it was published at allocation.
  let manifest: RunManifest

  var identifier: RunIdentifier {
    manifest.identifier
  }
}
