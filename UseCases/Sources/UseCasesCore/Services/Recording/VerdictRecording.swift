import Foundation

/// Stores the verdict a person or agent supplies for one route (chapter 13 §12). The request is
/// planned first and committed second, so every refusal comes before the first byte is written.
public protocol VerdictRecording: Sendable {
  /// Checks the request against the workspace and fingerprints the route it names: the route
  /// has to exist on a READY use case, and the status has to be one the store keeps. Writes
  /// nothing.
  ///
  /// The use case is an id or the start of exactly one id, and an exact id wins. The route is
  /// likewise a route id or the start of exactly one.
  ///
  /// - Parameters:
  ///   - request: What was asked.
  ///   - workspace: A workspace that loaded.
  ///   - links: What link resolution found in that workspace.
  func plan(
    _ request: RecordRequest,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(RecordingError) -> RecordPlan

  /// The use cases that can be recorded against, with their routes: the READY ones, in the order
  /// the workspace lists them (chapter 16 §12). `record --interactive` offers these.
  func offers(in workspace: LoadedWorkspace) -> [RecordOffer]

  /// Reads every attachment as ``plan(_:in:links:)`` would, so that a request that asks for them
  /// can be refused before anything else is asked of the person. Writes nothing.
  func checkAttachments(at locations: [URL]) throws(RecordingError)

  /// Allocates a run of kind `record`, appends the planned result and seals the run. The
  /// verdict is evidence once this returns.
  func commit(_ plan: RecordPlan) throws(RecordingError) -> RecordedRun
}
