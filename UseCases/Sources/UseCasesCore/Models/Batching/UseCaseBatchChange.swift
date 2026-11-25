import Foundation

/// A batch ready to be checked and written (chapter 16 §14, ADR 031): what became of each use
/// case in the order the batch runs, the files it changes, once each, and what it has to say
/// about them. Nothing is written yet.
public struct UseCaseBatchChange: Equatable, Sendable {
  /// Every use case of the batch in the order it runs: every removal, then every addition, then
  /// every update.
  public let useCases: [BatchedUseCase]

  /// The canonical folder of the workspace root the paths are relative to.
  public let root: URL

  /// The files to write, one change a file, by path; empty when every use case is already as
  /// sent.
  public let writes: WritePlan

  /// What the person is told besides: the comments that cannot follow a rewritten use case, and
  /// the markers that still name a removed one.
  public let warnings: [String]

  let expectations: [UseCaseExpectation]

  /// What the workspace as the batch would leave it holds that the batch did not mean; `nil`
  /// when it holds exactly what the batch meant.
  ///
  /// - Parameter workspace: The workspace loaded through the plan's view.
  public func divergence(in workspace: LoadedWorkspace) -> String? {
    expectations.divergence(in: workspace)
  }
}
