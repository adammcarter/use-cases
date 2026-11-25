/// Plans the batch of a proposal through the planner `apply` uses, so a brief or a proposal is
/// drawn only for a file `apply` would take.
struct ProposalBatchChecker: ProposalBatchChecking {
  private let planner: any UseCaseBatchPlanning

  init(planner: any UseCaseBatchPlanning = UseCaseBatchPlanner()) {
    self.planner = planner
  }

  func check(
    _ proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) {
    do {
      // Links only add warnings about markers that still name a removed use case.
      _ = try planner.plan(
        proposal.batch,
        approvedBy: nil,
        in: workspace,
        links: [],
      )
    } catch {
      throw .batch(error)
    }
  }
}
