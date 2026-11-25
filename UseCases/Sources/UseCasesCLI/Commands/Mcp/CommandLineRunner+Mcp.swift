extension CommandLineRunner {
  /// The server is not raced against a cancellation: it ends on a cancellation itself, after it
  /// has stopped every call still running.
  func result(of mcp: McpCommand) async -> CommandResult {
    await mcp.result(
      server: toolServer,
      shutdown: cancellation,
      workingDirectory: workingDirectory,
      folders: folders,
    )
  }
}
