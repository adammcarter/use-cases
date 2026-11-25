import ArgumentParser
import Foundation
import UseCasesCore

/// The `use-cases` command line (chapter 16).
public struct UseCasesCommand: ParsableCommand {
  /// How the command names and describes itself.
  public static let configuration = CommandConfiguration(
    commandName: "use-cases",
    abstract: "Use cases: the behaviour your code promises, and the proof it keeps that promise.",
    subcommands: [
      ValidateCommand.self,
      StatusCommand.self,
      LinksCommand.self,
      RecordCommand.self,
      VerifyCommand.self,
      InitCommand.self,
      ShowCommand.self,
      SaveCommand.self,
      RemoveCommand.self,
      ApplyCommand.self,
      ApproveCommand.self,
      RenderCommand.self,
      SearchCommand.self,
      DocsCommand.self,
      HooksCommand.self,
      PruneCommand.self,
      McpCommand.self,
    ],
  )

  /// The names of the commands, as a command line spells them.
  static let commandNames: Set = [
    ValidateCommand.name,
    StatusCommand.name,
    LinksCommand.name,
    RecordCommand.name,
    VerifyCommand.name,
    InitCommand.name,
    ShowCommand.name,
    SaveCommand.name,
    RemoveCommand.name,
    ApplyCommand.name,
    ApproveCommand.name,
    RenderCommand.name,
    SearchCommand.name,
    DocsCommand.name,
    HooksCommand.name,
    PruneCommand.name,
    McpCommand.name,
  ]

  @Flag(
    name: .long,
    help: "Print the version.",
  )
  var version = false

  @OptionGroup
  var global: GlobalOptions

  var json: Bool {
    global.json
  }

  /// Makes the command, ready for its arguments.
  public init() {}

  /// Runs the command line of this process and exits with its code (chapter 16 §6). Arguments
  /// that cannot be read are a refusal with exit 2, not ArgumentParser's own exit code.
  public static func main() async {
    await main(toolServer: UnavailableToolServing())
  }

  /// Runs the command line of this process as ``main()`` does, with `toolServer` serving
  /// `use-cases mcp`: the executable wires the MCP surface in here (ADR 038).
  public static func main(toolServer: any ToolServing) async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let colour = ColourRule(
      terminal: SystemTerminal(),
      environment: ProcessInfo.processInfo.environment,
    )
    let result = await CommandLineRunner(
      loader: WorkspaceLoader(),
      resolver: LinkResolver(),
      targeter: UseCaseTargeter(),
      cancellation: SignalCancellationScope(),
      deliver: { result in
        result.write()
      },
      isTerminal: isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0,
      program: ProgramPath(
        command: CommandLine.arguments.first ?? "use-cases",
        workingDirectory: workingDirectory,
        searchPath: ProcessInfo.processInfo.environment["PATH"],
        isExecutable: { path in
          FileManager.default.isExecutableFile(atPath: path)
        },
      ),
      workingDirectory: workingDirectory,
      toolServer: toolServer,
      folders: ExistingFolders(),
      showsColour: colour.allowsColour,
    ).run(arguments: arguments)

    Foundation.exit(result.exitCode)
  }

  /// What the bare command does: print the version when asked, and otherwise the help.
  func result() -> CommandResult {
    guard version else {
      // A script that asked for JSON and named no command is told so, in JSON. A person who
      // typed the bare command gets the help; `--help` is always the help.
      guard json else {
        return .done(CommandList.text)
      }

      return .refusal(
        .usage,
        message: "no command given; run `use-cases --help` to list them",
        command: nil,
        json: true,
      )
    }

    let report = VersionReport(version: .current)

    do {
      return try .done(json ? report.jsonText() : report.humanText())
    } catch {
      return .refusal(
        .refused,
        message: "the version could not be written as JSON",
        command: "version",
        json: json,
      )
    }
  }
}
