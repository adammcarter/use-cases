import Foundation
import UseCasesCore

/// The server of a command line that was given none: it says so, and serves nothing.
struct UnavailableToolServing: ToolServing {
  func serve(
    workingDirectory _: URL,
    workspace _: String?,
    shutdown _: any CancellationObserving,
  ) async -> ToolServingEnding {
    .failed(reason: "this build of use-cases has no MCP server")
  }
}
