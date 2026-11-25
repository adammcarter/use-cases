import Foundation
import UseCasesCore

/// What `render` draws its layouts with.
struct RenderTools {
  let intents: any IntentRendering
  let briefs: any BriefRendering
  let proposals: any ProposalRendering
  let results: any ResultsRendering

  /// - Parameters:
  ///   - workingDirectory: Where a relative path given to `--file` is read from.
  ///   - intents: Draws the intent.
  ///   - briefs: Draws the cards.
  ///   - proposals: Draws the proposal.
  ///   - results: Draws the results.
  init(
    workingDirectory: URL,
    intents: (any IntentRendering)? = nil,
    briefs: (any BriefRendering)? = nil,
    proposals: (any ProposalRendering)? = nil,
    results: (any ResultsRendering)? = nil,
  ) {
    self.intents = intents ?? IntentRenderer(workingDirectory: workingDirectory)
    self.briefs = briefs ?? BriefRenderer(workingDirectory: workingDirectory)
    self.proposals = proposals ?? ProposalRenderer(workingDirectory: workingDirectory)
    self.results = results ?? ResultsRenderer(workingDirectory: workingDirectory)
  }
}
