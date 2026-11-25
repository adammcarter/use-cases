extension CommandLineRunner {
  func result(of apply: ApplyCommand) async -> CommandResult {
    await raced(
      command: ApplyCommand.name,
      json: apply.global.json,
    ) {
      await apply.result(
        loader: loader,
        tools: signOff,
        writer: signOffWriter,
        workingDirectory: workingDirectory,
      )
    }
  }

  func result(of approve: ApproveCommand) async -> CommandResult {
    await raced(
      command: ApproveCommand.name,
      json: approve.global.json,
    ) {
      await approve.result(
        loader: loader,
        tools: signOff,
        writer: signOffWriter,
        workingDirectory: workingDirectory,
      )
    }
  }
}
