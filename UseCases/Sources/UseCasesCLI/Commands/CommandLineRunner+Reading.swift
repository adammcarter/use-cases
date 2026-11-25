extension CommandLineRunner {
  func result(of validate: ValidateCommand) async -> CommandResult {
    await raced(
      command: ValidateCommand.name,
      json: validate.global.json,
    ) {
      await validate.result(
        loader: loader,
        workingDirectory: workingDirectory,
      )
    }
  }

  func result(of links: LinksCommand) async -> CommandResult {
    await raced(
      command: LinksCommand.name,
      json: links.global.json,
    ) {
      await links.result(
        loader: loader,
        targeter: targeter,
        workingDirectory: workingDirectory,
      )
    }
  }

  func result(of status: StatusCommand) async -> CommandResult {
    await raced(
      command: StatusCommand.name,
      json: status.global.json,
    ) {
      await status.result(
        loader: loader,
        judge: judge,
        targeter: targeter,
        groupSelector: groupSelector,
        workingDirectory: workingDirectory,
      )
    }
  }
}
