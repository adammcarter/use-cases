import Foundation

/// Draws the proposal from the proposal file and the workspace.
public struct ProposalRenderer: ProposalRendering {
  private let reader: any ProposalFileReading
  private let resolver: any ProposalChangeResolving
  private let checker: any ProposalBatchChecking

  /// Makes the renderer.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  public init(workingDirectory: URL) {
    self.init(
      reader: ProposalFileReader(workingDirectory: workingDirectory),
      resolver: ProposalChangeResolver(),
      checker: ProposalBatchChecker(),
    )
  }

  init(
    reader: any ProposalFileReading,
    resolver: any ProposalChangeResolving,
    checker: any ProposalBatchChecking,
  ) {
    self.reader = reader
    self.resolver = resolver
    self.checker = checker
  }

  public func proposal(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> ProposalLayout {
    let proposal = try reader.read(argument)
    try checker.check(
      proposal,
      in: workspace,
    )
    let changes = try resolver.changes(
      of: proposal,
      in: workspace,
    )

    return ProposalLayout(
      title: proposal.title,
      changes: changes.map { change in
        ProposalChange(
          change: change,
          youSee: proposal.youSee[change.identifier],
        )
      },
      decisions: proposal.decisions,
      signOff: SignOffCounts(counting: changes),
    )
  }
}
