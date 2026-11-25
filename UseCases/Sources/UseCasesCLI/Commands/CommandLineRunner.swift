import ArgumentParser
import Foundation
import UseCasesCore

/// Reads the arguments of one run and does what they say, without touching the terminal: the
/// answer is a ``CommandResult``.
struct CommandLineRunner {
  let loader: any LinkedWorkspaceLoading
  let targeter: any UseCaseTargeting
  let groupSelector: any GroupSelecting
  private let shower: any UseCaseShowing
  let search: SearchTools
  let edit: EditTools
  let signOff: SignOffTools
  let signOffWriter: any SignOffWriting
  let render: RenderTools
  private let surface: any CommandSurfacing
  private let recorder: any VerdictRecording
  let judge: any StatusJudging
  let prompter: any Prompting
  let verifier: Verifier
  let initializer: any WorkspaceInitializing
  let hooks: any HookPlanning
  let pruner: any StorePruning
  let write: any PlanCarrying
  let cancellation: any CancellationScoping
  private let deliver: @Sendable (CommandResult) async -> Void
  let isTerminal: Bool
  let program: String
  let workingDirectory: URL
  let toolServer: any ToolServing
  let folders: any FolderChecking
  let showsColour: Bool
  private let clock: any Clock<Duration>

  /// - Parameters:
  ///   - edit: What `save` and `remove` plan their changes with.
  ///   - signOff: What `apply` and `approve` plan their changes with.
  ///   - signOffWriter: What checks and writes their changes. Left out, it writes through the
  ///     shared writer.
  ///   - write: What checks and writes the changes of `init` and `hooks`, and of `save`, `remove`,
  ///     `apply` and `approve` when no writer of their own is given. Left out, it checks through
  ///     `viewer` and writes through `writer`.
  ///   - render: What `render` draws its layouts with.
  ///   - prompter: How `record --interactive` asks the person.
  ///   - initializer: Plans what `init` writes.
  ///   - hooks: Plans the git hooks of `hooks` and `init --hooks`. Left out, it asks the `git` on
  ///     the PATH.
  ///   - pruner: Plans and removes the superseded runs of `prune`.
  ///   - viewer: Shows the workspace as a change would leave it, to check it before it is written.
  ///   - writer: Writes the files of a change, all or nothing.
  ///   - cancellation: Watches for SIGINT, SIGTERM and SIGHUP for as long as a command runs, and
  ///     until its answer has been delivered. A command that reads only is answered at once with
  ///     the cancellation; one that writes stops before it writes, or finishes the write.
  ///   - deliver: Takes the answer of a command line, once, while the signals are still held:
  ///     production writes it to the terminal here.
  ///   - isTerminal: Whether a person is at a terminal (standard input and output), which
  ///     `record --interactive` and the questions of `init` need.
  ///   - program: The full path of the `use-cases` that is running, which a hook remembers.
  ///   - toolServer: Serves the commands as MCP tools for `use-cases mcp`. Left out, the command
  ///     says this build has none.
  ///   - folders: Says whether the workspace `use-cases mcp --workspace` names is a folder. Left
  ///     out, every folder is taken to be there.
  ///   - showsColour: Whether a layout's headers may be bold: the colour rule of chapter 16 §19
  ///     allows it. Left out, they are plain.
  ///   - clock: What the watcher of a command's cancellation waits on between two looks. Left
  ///     out, the continuous clock.
  init(
    loader: any WorkspaceLoading,
    transformers: any TransformerLinkProviding = TransformerLinkResolver(),
    resolver: any LinkResolving = LinkResolver(),
    targeter: any UseCaseTargeting = UseCaseTargeter(),
    groupSelector: any GroupSelecting = GroupSelector(),
    shower: any UseCaseShowing = UseCaseShower(),
    search: SearchTools? = nil,
    edit: EditTools? = nil,
    signOff: SignOffTools? = nil,
    signOffWriter: (any SignOffWriting)? = nil,
    write: (any PlanCarrying)? = nil,
    render: RenderTools? = nil,
    surface: any CommandSurfacing = CommandSurface(),
    recorder: any VerdictRecording = VerdictRecorder(),
    judge: any StatusJudging = StatusJudge(),
    prompter: any Prompting = TerminalPrompter(),
    verifier: Verifier = Verifier(),
    initializer: any WorkspaceInitializing = WorkspaceInitializer(),
    hooks: (any HookPlanning)? = nil,
    pruner: any StorePruning = StorePruner(),
    viewer: any PlanViewing = OverlayPlanViewer(),
    writer: any PlanWriting = AtomicPlanWriter(),
    cancellation: any CancellationScoping = ObservedCancellationScope(
      makeObserver: {
        NoCancellation()
      },
    ),
    deliver: @escaping @Sendable (CommandResult) async -> Void = { _ in },
    isTerminal: Bool = false,
    program: ProgramPath = ProgramPath(
      installedAt: ProgramPath.installed,
    ),
    workingDirectory: URL,
    toolServer: any ToolServing = UnavailableToolServing(),
    folders: any FolderChecking = UncheckedFolders(),
    showsColour: Bool = false,
    clock: any Clock<Duration> = ContinuousClock(),
  ) {
    let linked = LinkedWorkspaceLoader(
      loader: loader,
      transformers: transformers,
      resolver: resolver,
    )
    self.loader = linked
    self.targeter = targeter
    self.groupSelector = groupSelector
    self.shower = shower
    self.search = search ?? SearchTools(workingDirectory: workingDirectory)
    self.edit = edit ?? EditTools(workingDirectory: workingDirectory)
    self.signOff = signOff ?? SignOffTools(workingDirectory: workingDirectory)
    self.render = render ?? RenderTools(workingDirectory: workingDirectory)
    self.surface = surface
    self.recorder = recorder
    self.judge = judge
    self.prompter = prompter
    self.verifier = verifier
    self.initializer = initializer
    self.hooks = hooks ?? HookPlanner(git: GitInspector(cancellation: cancellation))
    self.pruner = pruner
    let planned = write ?? PlannedWrite(
      viewer: viewer,
      writer: writer,
      transformers: transformers,
      cancellation: cancellation,
    )
    self.write = planned
    self.signOffWriter = signOffWriter ?? SignOffWriter(write: planned)
    self.cancellation = cancellation
    self.deliver = deliver
    self.isTerminal = isTerminal
    self.program = program.text
    self.workingDirectory = workingDirectory
    self.toolServer = toolServer
    self.folders = folders
    self.showsColour = showsColour
    self.clock = clock
  }

  func run(arguments: [String]) async -> CommandResult {
    // The command list, a command that does not exist and one not built yet are answered before
    // any command reads the line.
    if let answer = surface.answer(to: arguments) {
      await deliver(answer)

      return answer
    }

    let command: any ParsableCommand

    do {
      command = try UseCasesCommand.parseAsRoot(arguments)
    } catch {
      let result = result(
        forUnreadable: error,
        arguments: arguments,
      )
      await deliver(result)

      return result
    }

    // The signals are ours from here until the answer is written, so that none of them falls
    // between two parts of a command, or between the command and its document, where the
    // default action would end the process with no document and a run open.
    let holdsSignals = !asksQuestions(command)

    if holdsSignals {
      await cancellation.begin()
    }

    let result = await result(
      of: command,
      arguments: arguments,
    )
    await deliver(result)

    if holdsSignals {
      await cancellation.end()
    }

    return result
  }

  private func result(
    of command: any ParsableCommand,
    arguments: [String],
  ) async -> CommandResult {
    switch command {
    case let validate as ValidateCommand:
      await result(of: validate)
    case let links as LinksCommand:
      await result(of: links)
    case let status as StatusCommand:
      await result(of: status)
    case let search as SearchCommand:
      await result(of: search)
    case let show as ShowCommand:
      await result(of: show)
    case let docs as DocsCommand:
      await result(of: docs)
    case let record as RecordCommand:
      await result(of: record)
    case let verify as VerifyCommand:
      await result(of: verify)
    case let root as UseCasesCommand:
      root.result()
    default:
      await setUpResult(
        of: command,
        arguments: arguments,
      )
    }
  }

  private func result(of show: ShowCommand) async -> CommandResult {
    await raced(
      command: ShowCommand.name,
      json: show.global.json,
    ) {
      await show.result(
        loader: loader,
        shower: shower,
        workingDirectory: workingDirectory,
      )
    }
  }

  /// A person at a prompt must still be able to stop it with Ctrl-C, so `--interactive` is not
  /// watched until its write.
  private func result(of record: RecordCommand) async -> CommandResult {
    let work: @Sendable () async -> CommandResult = {
      await record.result(
        loader: loader,
        session: RecordSession(
          recorder: recorder,
          prompter: prompter,
          cancellation: cancellation,
          isTerminal: isTerminal,
        ),
        workingDirectory: workingDirectory,
      )
    }

    guard !record.interactive else {
      return await work()
    }

    return await raced(
      command: RecordCommand.name,
      json: record.global.json,
      work,
    )
  }

  /// `--finish` and `--run` tell their own cancellation; every other step answers it at once, or
  /// writes and says so.
  private func result(of verify: VerifyCommand) async -> CommandResult {
    let work: @Sendable () async -> CommandResult = {
      await verify.result(
        loader: loader,
        verifier: verifier,
        cancellation: cancellation,
        workingDirectory: workingDirectory,
      )
    }

    guard !verify.reportsOwnCancellation else {
      return await work()
    }

    return await raced(
      command: VerifyCommand.name,
      json: verify.global.json,
      work,
    )
  }

  /// Does the work of a command, and answers a cancellation as soon as it comes, whatever the
  /// work is doing, so that a command hashing a huge file is not waited for. The cancelled work
  /// is left to the end of the process; it writes nothing, because it claims its write from the
  /// cancellation, which refuses once it has come. Work that has begun to write is never
  /// abandoned: its answer is waited for (chapter 13 §15).
  func raced(
    command: String,
    json: Bool,
    _ work: @escaping @Sendable () async -> CommandResult,
  ) async -> CommandResult {
    let cancelled = CommandResult.cancelled(
      command: command,
      json: json,
    )

    guard await !cancellation.isCancelled() else {
      return cancelled
    }

    let (answers, delivery) = AsyncStream.makeStream(of: CommandResult.self)
    let scope = cancellation
    let clock = clock

    Task {
      await delivery.yield(work())
      delivery.finish()
    }

    let watching = Task {
      while !Task.isCancelled {
        if await scope.isCancelled(), await !scope.isWriting() {
          delivery.yield(cancelled)
          delivery.finish()

          return
        }

        try? await clock.sleep(for: .milliseconds(20))
      }
    }

    var answer: CommandResult?

    for await next in answers {
      answer = next
      break
    }

    watching.cancel()

    return answer ?? cancelled
  }

  /// A command none of the cases above knows is run as ArgumentParser would, which is how a
  /// request for help comes back as an answer.
  func helpResult(
    of command: any ParsableCommand,
    arguments: [String],
  ) -> CommandResult {
    var help = command

    do {
      try help.run()
    } catch {
      return result(
        forUnreadable: error,
        arguments: arguments,
      )
    }

    return .done(CommandList.text)
  }

  /// `--help` is an answer; anything else ArgumentParser refused is a usage error. A command
  /// line that was not read has no options to ask, so `--json` is looked for in the text.
  private func result(
    forUnreadable error: any Error,
    arguments: [String],
  ) -> CommandResult {
    if UseCasesCommand.exitCode(for: error) == .success {
      return .done(UseCasesCommand.fullMessage(for: error))
    }

    let words = arguments.prefix { word in
      word != "--"
    }

    return .refusal(
      .usage,
      message: UseCasesCommand.message(for: error),
      command: words.first { word in
        UseCasesCommand.commandNames.contains(word)
      },
      json: words.contains("--json"),
    )
  }
}
