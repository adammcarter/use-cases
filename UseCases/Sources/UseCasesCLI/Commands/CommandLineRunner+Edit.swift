extension CommandLineRunner {
  func result(of save: SaveCommand) async -> CommandResult {
    await raced(
      command: SaveCommand.name,
      json: save.global.json,
    ) {
      await save.result(
        loader: loader,
        tools: edit,
        writer: EditWriter(write: write),
        workingDirectory: workingDirectory,
      )
    }
  }

  func result(of remove: RemoveCommand) async -> CommandResult {
    await raced(
      command: RemoveCommand.name,
      json: remove.global.json,
    ) {
      await remove.result(
        loader: loader,
        tools: edit,
        writer: EditWriter(write: write),
        workingDirectory: workingDirectory,
      )
    }
  }
}
