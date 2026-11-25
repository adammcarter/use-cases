import Foundation
import UseCasesCLI
import UseCasesCore
import UseCasesMCP

/// Gives `use-cases mcp` the tool server of the MCP surface: the one place the command line and
/// the tools meet (ADR 038).
struct MCPToolServing: ToolServing {
  private let executable: any RunningExecutableLocating

  /// - Parameter executable: Says where the running `use-cases` is, which each tool call runs.
  init(executable: any RunningExecutableLocating = RealExecutableLocator()) {
    self.executable = executable
  }

  func serve(
    workingDirectory: URL,
    workspace: String?,
    shutdown: any CancellationObserving,
  ) async -> ToolServingEnding {
    guard let program = executable.executableLocation() else {
      return .failed(reason: "the running use-cases cannot be found, so it cannot run its tools")
    }

    let server = ToolServer(
      program: program,
      workingDirectory: workingDirectory,
      workspace: workspace,
    )

    do {
      switch try await server.run(shutdown: shutdown) {
      case .inputClosed:
        return .inputClosed
      case .stopped:
        return .stopped
      }
    } catch {
      return .failed(reason: "\(error)")
    }
  }
}
