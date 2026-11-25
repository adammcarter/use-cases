import Foundation

/// Plans `apply`: reads the batch, then plans it as one run of edits.
public struct UseCaseApplier: UseCaseApplying {
  private let reader: any UseCaseBatchReading
  private let planner: any UseCaseBatchPlanning

  /// Makes the applier.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  public init(workingDirectory: URL) {
    self.init(
      reader: UseCaseBatchReader(workingDirectory: workingDirectory),
      planner: UseCaseBatchPlanner(),
    )
  }

  init(
    reader: any UseCaseBatchReading,
    planner: any UseCaseBatchPlanning,
  ) {
    self.reader = reader
    self.planner = planner
  }

  public func plan(
    applyingFrom argument: String,
    approvedBy approver: String?,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseBatchError) -> UseCaseBatchChange {
    var name: ApproverName?

    if let approver {
      do {
        name = try ApproverName(validating: approver)
      } catch {
        throw .approver(reason: error.message(of: "--approved-by"))
      }
    }

    return try planner.plan(
      reader.read(argument),
      approvedBy: name,
      in: workspace,
      links: links,
    )
  }
}
