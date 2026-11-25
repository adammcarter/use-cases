import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases mcp` (chapter 20): the MCP server an agent's host starts. Not typed by people.
/// Standard output carries the protocol and nothing else.
struct McpCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "The MCP server an agent's host starts: the commands as tools, over stdio.",
  )

  static let name = "mcp"

  @OptionGroup
  var global: GlobalOptions

  /// Serves through `server` and answers how that ended: exit 0 when the host closed its input,
  /// 130 when the process was told to stop (chapter 16 §6), 2 when the server could not be run,
  /// or when the workspace it was given is not a folder, as every command refuses one.
  func result(
    server: any ToolServing,
    shutdown: any CancellationObserving,
    workingDirectory: URL,
    folders: any FolderChecking = UncheckedFolders(),
  ) async -> CommandResult {
    // Named, calls use it; unnamed, each call finds the workspace from where the server is.
    let workspace = global.workspace == nil ? nil : global.folder(from: workingDirectory).path

    if let workspace, !folders.isFolder(URL(fileURLWithPath: workspace)) {
      return CommandResult(
        standardOutput: "",
        standardError: "error: '\(workspace)' has no use-cases.yml; the workspace root is the "
          + "folder whose use-cases.yml says root: true\n",
        exitCode: 2,
      )
    }

    let ending = await server.serve(
      workingDirectory: workingDirectory,
      workspace: workspace,
      shutdown: shutdown,
    )

    switch ending {
    case .inputClosed:
      return CommandResult(
        standardOutput: "",
        standardError: "",
        exitCode: 0,
      )
    case .stopped:
      return CommandResult(
        standardOutput: "",
        standardError: "",
        exitCode: 130,
      )
    case let .failed(reason):
      return CommandResult(
        standardOutput: "",
        standardError: "error: \(reason)\n",
        exitCode: 2,
      )
    }
  }
}
