import Foundation
@testable import UseCasesCore

/// A planner that plans the line as told whatever the folder holds, and notes the folders it is
/// asked about, on a stream.
struct StubGitignorePlanning: GitignorePlanning {
  /// The folders asked about, in order, until ``asked()``.
  let roots: AsyncStream<URL>

  private let noting: AsyncStream<URL>.Continuation
  private let answer: GitignorePlanner.Plan

  init(answering answer: GitignorePlanner.Plan) {
    (roots, noting) = AsyncStream.makeStream(of: URL.self)
    self.answer = answer
  }

  /// Every folder asked about so far.
  func asked() async -> [URL] {
    noting.finish()

    var found: [URL] = []

    for await root in roots {
      found.append(root)
    }

    return found
  }

  func plan(for root: URL) throws(InitError) -> GitignorePlanner.Plan {
    noting.yield(root)

    return answer
  }
}
