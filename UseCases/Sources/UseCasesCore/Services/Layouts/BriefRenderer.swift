import Foundation

/// Draws the cards of a proposal from the proposal file and the workspace.
public struct BriefRenderer: BriefRendering {
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

  public func brief(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> BriefLayout {
    let proposal = try reader.read(argument)
    try checker.check(
      proposal,
      in: workspace,
    )
    let changes = try resolver.changes(
      of: proposal,
      in: workspace,
    )

    return BriefLayout(
      cards: changes.filter { change in
        change.fit != .untouched
      }.map { change in
        BriefCard(
          change: change,
          golden: proposal.golden[change.identifier],
        )
      },
    )
  }
}
