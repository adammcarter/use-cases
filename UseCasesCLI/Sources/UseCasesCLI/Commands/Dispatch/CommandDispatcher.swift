/// Runs a matched command (packages/cli/src/command/dispatch.ts
/// `runRegistryCommand`): parse its flags, call its handler, render what it
/// returns. A thrown failure becomes the standard error envelope, labelled by
/// the command's PATH rather than its id, with exit 1 — as in the TypeScript.
enum CommandDispatcher {
  static func run(
    _ command: CommandSpecification,
    arguments: [String],
    isJSON: Bool,
  ) -> CliOutcome {
    let output: CommandOutput
    do throws(CommandFailure) {
      let flags = ArgumentScanner.parseFlags(arguments, specifications: command.flags)
      output = try command.handler(
        HandlerContext(arguments: arguments, flags: flags, isJSON: isJSON),
      )
    } catch {
      output = CommandOutput(
        result: ErrorEnvelope.make(
          command: command.path.joined(separator: "."),
          code: error.code,
          message: error.message,
        ),
        exitCode: 1,
      )
    }
    return CliOutcome(
      standardOutput: EnvelopeRenderer.render(output.envelope, isJSON: isJSON),
      exitCode: output.exitCode,
    )
  }
}
