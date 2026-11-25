import Foundation

/// A `save` or `remove` ready to be checked and written (chapter 16 §14): what it does to one
/// use case, the files it changes and what it has to say about them. Nothing is written yet.
public struct UseCaseChange: Equatable, Sendable {
  /// The full id of the use case.
  public let identifier: String

  /// The definition file the use case is in, or was in, relative to the workspace root.
  public let file: String

  public let action: UseCaseChangeAction

  /// The canonical folder of the workspace root the paths are relative to.
  public let root: URL

  /// The files to write; empty when the use case is already as it was sent.
  public let writes: WritePlan

  /// What the person is told besides: the comments that cannot follow a rewritten use case, and
  /// the markers that still name a removed one.
  public let warnings: [String]

  let expectation: UseCaseExpectation

  /// What the workspace as the change would leave it holds that the change did not mean; `nil`
  /// when it holds exactly what the change meant.
  ///
  /// - Parameter workspace: The workspace loaded through the plan's view.
  public func divergence(in workspace: LoadedWorkspace) -> String? {
    expectation.divergence(in: workspace)
  }
}
