extension CommandLineRunner {
  func result(of search: SearchCommand) async -> CommandResult {
    await raced(
      command: SearchCommand.name,
      json: search.global.json,
    ) {
      await search.result(
        loader: loader,
        judge: judge,
        tools: self.search,
        workingDirectory: workingDirectory,
      )
    }
  }
}
