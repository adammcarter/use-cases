import Foundation

/// Shows a workspace as a plan would leave it, so the plan can be checked without a copy of the
/// workspace and without writing a byte (`docs/architecture.md` §2).
public protocol PlanViewing: Sendable {
  /// - Parameters:
  ///   - plan: What would be written.
  ///   - root: The workspace root the plan's paths are relative to.
  /// - Returns: The loader and resolver that read the workspace with the plan laid over it.
  /// - Throws: ``PlanWritingError`` when the plan conflicts with what is there, as the writer
  ///   would refuse it: a file to create that exists, a file to replace that does not.
  func view(
    showing plan: WritePlan,
    in root: URL,
  ) throws(PlanWritingError) -> WorkspaceView
}
