import ArgumentParser
import UseCasesCore

extension CommandLineRunner {
  /// The commands that set up or change things beside the workspace's model, the server that
  /// serves them, or the help of one none of the cases above knows.
  func setUpResult(
    of command: any ParsableCommand,
    arguments: [String],
  ) async -> CommandResult {
    switch command {
    case let initialize as InitCommand:
      await result(of: initialize)
    case let hooks as HooksCommand:
      await result(of: hooks)
    case let prune as PruneCommand:
      await result(of: prune)
    case let save as SaveCommand:
      await result(of: save)
    case let remove as RemoveCommand:
      await result(of: remove)
    case let mcp as McpCommand:
      await result(of: mcp)
    case let apply as ApplyCommand:
      await result(of: apply)
    case let approve as ApproveCommand:
      await result(of: approve)
    case let render as RenderCommand:
      await result(of: render)
    default:
      helpResult(
        of: command,
        arguments: arguments,
      )
    }
  }

  /// A person at a prompt must still be able to stop it with Ctrl-C: `record --interactive` and
  /// an `init` that asks hold the signals for their write alone.
  func asksQuestions(_ command: any ParsableCommand) -> Bool {
    if let record = command as? RecordCommand {
      return record.interactive
    }

    if let initialize = command as? InitCommand {
      return initialize.asksQuestions(isTerminal: isTerminal)
    }

    return false
  }

  func result(of initialize: InitCommand) async -> CommandResult {
    let work: @Sendable () async -> CommandResult = {
      await initialize.result(
        session: InitSession(
          initializer: initializer,
          hooks: hooks,
          prompter: prompter,
          write: write,
          cancellation: cancellation,
          program: program,
          isTerminal: isTerminal,
        ),
        workingDirectory: workingDirectory,
      )
    }

    guard !initialize.asksQuestions(isTerminal: isTerminal) else {
      return await work()
    }

    return await raced(
      command: InitCommand.name,
      json: initialize.global.json,
      work,
    )
  }

  func result(of prune: PruneCommand) async -> CommandResult {
    await raced(
      command: PruneCommand.name,
      json: prune.global.json,
    ) {
      await prune.result(
        session: PruneSession(
          loader: loader,
          pruner: pruner,
          cancellation: cancellation,
        ),
        workingDirectory: workingDirectory,
      )
    }
  }

  func result(of hooks: HooksCommand) async -> CommandResult {
    await raced(
      command: HooksCommand.name,
      json: hooks.global.json,
    ) {
      await hooks.result(
        session: HooksSession(
          locator: verifier.locator,
          planner: self.hooks,
          write: write,
          program: program,
        ),
        workingDirectory: workingDirectory,
      )
    }
  }
}
