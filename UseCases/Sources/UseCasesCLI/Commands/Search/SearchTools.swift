import Foundation
import UseCasesCore

/// What `search` is done with: reading what was typed, and finding the matches.
struct SearchTools {
  let planner: any SearchPlanning
  let searcher: any UseCaseSearching

  /// - Parameters:
  ///   - workingDirectory: Where a relative path given to `--like` is read from.
  ///   - planner: Reads the flags, the words, the `--like` use case and the token.
  ///   - searcher: Finds the matches.
  init(
    workingDirectory: URL,
    planner: (any SearchPlanning)? = nil,
    searcher: any UseCaseSearching = UseCaseSearcher(),
  ) {
    self.planner = planner ?? SearchPlanner(workingDirectory: workingDirectory)
    self.searcher = searcher
  }
}
