extension CommandLineRunner {
  func result(of command: RenderCommand) async -> CommandResult {
    await raced(
      command: RenderCommand.name,
      json: command.global.json,
    ) {
      await command.result(
        loader: loader,
        tools: render,
        style: showsColour ? .bold : .plain,
        workingDirectory: workingDirectory,
      )
    }
  }
}
