import Foundation
import UseCasesCore

/// Serves the commands as tools to an agent's host (chapter 20) until the host is done. The
/// command line knows nothing of how: the executable gives `use-cases mcp` the server it wires
/// (ADR 038), so this module never imports the MCP surface.
public protocol ToolServing: Sendable {
  /// Serves over the process's standard input and output until the host closes its input or
  /// `shutdown` says the process was told to stop.
  ///
  /// - Parameters:
  ///   - workingDirectory: The folder the server started in, where every call starts unless it
  ///     names a workspace.
  ///   - workspace: The workspace root `use-cases mcp --workspace` named, for a call that names
  ///     none; `nil` leaves each call to find the workspace from `workingDirectory`.
  ///   - shutdown: Says when SIGINT, SIGTERM or SIGHUP has come.
  func serve(
    workingDirectory: URL,
    workspace: String?,
    shutdown: any CancellationObserving,
  ) async -> ToolServingEnding
}
