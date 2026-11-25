import Foundation
import MCP
import UseCasesCore

/// Each call is the command itself, run as a separate process (ADR 027): `use-cases <command>
/// --json …`, from the folder the server started in, with the answer given back unchanged.
struct ToolCaller: ToolCalling {
  private let catalogue: ToolCatalogue
  private let program: URL
  private let workingDirectory: URL
  private let workspace: String?
  private let lifeline: Int32?
  private let runner: any CommandRunning
  private let builder: any ToolCommandLineBuilding
  private let mapper: any ToolResultMapping

  /// - Parameters:
  ///   - catalogue: The tools.
  ///   - program: The `use-cases` to run, by its real path.
  ///   - workingDirectory: The folder the server started in, where each command starts.
  ///   - workspace: The workspace root for a call that names none, if the server was given one.
  ///   - lifeline: The read end of the pipe each command is handed as its lifeline, if any.
  ///   - runner: Runs the command.
  ///   - builder: Makes the command line.
  ///   - mapper: Makes the result.
  init(
    catalogue: ToolCatalogue,
    program: URL,
    workingDirectory: URL,
    workspace: String?,
    lifeline: Int32? = nil,
    runner: any CommandRunning,
    builder: any ToolCommandLineBuilding = ToolCommandLineBuilder(),
    mapper: any ToolResultMapping = ToolResultMapper(),
  ) {
    self.catalogue = catalogue
    self.program = program
    self.workingDirectory = workingDirectory
    self.workspace = workspace
    self.lifeline = lifeline
    self.runner = runner
    self.builder = builder
    self.mapper = mapper
  }

  func call(_ parameters: CallTool.Parameters) async throws(ToolCallError) -> CallTool.Result {
    guard let entry = catalogue.entry(named: parameters.name) else {
      throw .unknownTool(parameters.name)
    }

    let command = entry.definition.command
    let arguments = parameters.arguments ?? [:]

    // A value the SDK made into data is not the text the host wrote, and is never passed on
    // altered in silence.
    if let name = arguments.keys.sorted().first(where: { arguments[$0]?.holdsData == true }) {
      return mapper.refusal(
        .usage(
          command: command,
          message: "\(name) looks like a data URL and was not read as the text it is",
        ),
      )
    }

    // Refused before anything runs.
    if let problem = entry.checker.refusal(of: arguments) {
      return mapper.refusal(
        .usage(
          command: command,
          message: problem,
        ),
      )
    }

    let line: ToolCommandLine

    do {
      line = try builder.commandLine(
        for: entry.definition,
        arguments: arguments,
        workspace: workspace,
      )
    } catch {
      return mapper.refusal(
        .usage(
          command: command,
          message: error.message,
        ),
      )
    }

    return try await run(
      line,
      command: command,
    )
  }

  private func run(
    _ line: ToolCommandLine,
    command: String,
  ) async throws(ToolCallError) -> CallTool.Result {
    let outcome: CommandOutcome

    do {
      outcome = try await runner.run(
        CommandInvocation(
          arguments: [program.path] + line.arguments,
          workingDirectory: workingDirectory,
          standardInput: line.standardInput,
          lifeline: lifeline,
        ),
      )
    } catch {
      return mapper.refusal(
        ToolErrorDocument(
          command: command,
          kind: "refused",
          message: "use-cases could not be run: \(error)",
        ),
      )
    }

    guard outcome.ending != .cancelled else {
      throw .cancelled
    }

    return mapper.result(
      for: outcome,
      command: command,
    )
  }
}
