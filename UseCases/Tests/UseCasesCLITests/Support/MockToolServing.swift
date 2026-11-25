import Foundation
import UseCasesCore
@testable import UseCasesCLI

/// A tool server that serves nothing: it ends as the test decides, and remembers what it was
/// asked to serve.
actor MockToolServing: ToolServing {
  struct Request: Equatable {
    let workingDirectory: URL
    let workspace: String?
  }

  private(set) var requests: [Request] = []
  private let ending: ToolServingEnding

  init(ending: ToolServingEnding) {
    self.ending = ending
  }

  func serve(
    workingDirectory: URL,
    workspace: String?,
    shutdown _: any CancellationObserving,
  ) async -> ToolServingEnding {
    requests.append(
      Request(
        workingDirectory: workingDirectory,
        workspace: workspace,
      ),
    )

    return ending
  }
}
