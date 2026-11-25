import Foundation

/// An `approve` ready to be checked and written (chapter 16 §14): the sign-off of each use case
/// as its promise reads now, the files it changes, and what it has to say about them. Nothing is
/// written yet.
public struct UseCaseApprovalChange: Equatable, Sendable {
  /// Who signed off, without the space around the name.
  public let approver: String

  /// Each use case asked for, in the order they were asked for, or by id under `--all`.
  public let useCases: [ApprovedUseCase]

  /// The canonical folder of the workspace root the paths are relative to.
  public let root: URL

  /// The files to write, one change a file, by path; empty when every use case was already
  /// approved as it reads.
  public let writes: WritePlan

  /// The comments that cannot follow a rewritten use case, one line each.
  public let warnings: [String]

  let expectations: [UseCaseExpectation]

  /// What the workspace as the sign-off would leave it holds that the sign-off did not mean;
  /// `nil` when it holds exactly what was meant.
  ///
  /// - Parameter workspace: The workspace loaded through the plan's view.
  public func divergence(in workspace: LoadedWorkspace) -> String? {
    expectations.divergence(in: workspace)
  }
}
