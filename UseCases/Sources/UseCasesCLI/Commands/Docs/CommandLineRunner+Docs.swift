import UseCasesCore

extension CommandLineRunner {
  /// `docs` needs no workspace: the guides are part of the build, so the answer is made from them
  /// and nothing else.
  func result(of docs: DocsCommand) async -> CommandResult {
    await raced(
      command: DocsCommand.name,
      json: docs.global.json,
    ) {
      docs.result(answerer: DocsAnswerer())
    }
  }
}
