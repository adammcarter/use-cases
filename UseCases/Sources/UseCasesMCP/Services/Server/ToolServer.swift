import Foundation
import MCP
import UseCasesCore

/// The MCP server of chapter 20: the commands as tools, over stdio, for an agent's host. It
/// serves tools only, says nothing the host did not ask, and keeps nothing between calls: each
/// call runs its command as a separate process (ADR 027).
///
/// Standard output carries the protocol and nothing else.
public struct ToolServer: Sendable {
  /// How long the command of a cancelled call gets to wind up (a `verify` run seals itself as
  /// cancelled, stopping its own tests) after SIGTERM before SIGKILL.
  public static let terminationGrace = Duration.seconds(10)

  private let program: URL
  private let workingDirectory: URL
  private let workspace: String?
  private let runner: any CommandRunning
  private let schemas: any OutputSchemaLoading

  /// - Parameters:
  ///   - program: The `use-cases` to run for each call, by its real path.
  ///   - workingDirectory: The folder the server started in, where each call starts unless it
  ///     names a workspace.
  ///   - workspace: The workspace root for a call that names none, if the server was given one.
  public init(
    program: URL,
    workingDirectory: URL,
    workspace: String? = nil,
  ) {
    self.init(
      program: program,
      workingDirectory: workingDirectory,
      workspace: workspace,
      runner: CommandRunner(terminationGrace: Self.terminationGrace),
      schemas: BundledOutputSchemas(),
    )
  }

  init(
    program: URL,
    workingDirectory: URL,
    workspace: String?,
    runner: any CommandRunning,
    schemas: any OutputSchemaLoading,
  ) {
    self.program = program
    self.workingDirectory = workingDirectory
    self.workspace = workspace
    self.runner = runner
    self.schemas = schemas
  }

  /// Serves on the process's standard input and output until the host closes its input or
  /// `shutdown` says the process was told to stop. Either way every call still running is
  /// cancelled, which stops its command, and waited for.
  public func run(
    shutdown: any CancellationObserving,
  ) async throws(ToolServerError) -> ToolServerEnding {
    // A host that has gone away ends a write with an error, which cancels the calls running; it
    // does not end this process, with the calls running, by a signal nobody sees.
    signal(SIGPIPE, SIG_IGN)

    let lifeline = try ServerLifeline()
    defer {
      lifeline.close()
    }

    return try await run(
      transport: StdioTransport(),
      watcher: ShutdownWatcher(observer: shutdown),
      lifeline: lifeline.readEnd,
    )
  }

  func run(
    transport: any Transport,
    watcher: any ShutdownWatching,
    lifeline: Int32? = nil,
  ) async throws(ToolServerError) -> ToolServerEnding {
    let catalogue: ToolCatalogue

    do {
      catalogue = try ToolCatalogue(schemas: schemas)
    } catch {
      throw .catalogue(reason: "\(error)")
    }

    let calls = RunningCalls()
    let arguments = ToolCallArguments()
    let server = Self.makeServer()

    await register(
      on: server,
      catalogue: catalogue,
      caller: ToolCaller(
        catalogue: catalogue,
        program: program,
        workingDirectory: workingDirectory,
        workspace: workspace,
        lifeline: lifeline,
        runner: runner,
      ),
      calls: calls,
      arguments: arguments,
    )

    do {
      try await server.start(
        transport: ToolTransport(
          transport: transport,
          logger: transport.logger,
          arguments: arguments,
        ),
      )
    } catch {
      throw .transport(reason: "\(error)")
    }

    let watching = Task {
      let isStopping = await watcher.waitsForShutdown()

      if isStopping {
        await server.stop()
      }

      return isStopping
    }

    await server.waitUntilCompleted()
    watching.cancel()
    let isStopped = await watching.value

    await calls.cancelAll()
    await server.stop()

    return isStopped ? .stopped : .inputClosed
  }

  private static func makeServer() -> Server {
    Server(
      name: ServerIdentity.name,
      version: ServerIdentity.version,
      title: ServerIdentity.title,
      capabilities: Server.Capabilities(tools: Server.Capabilities.Tools()),
    )
  }

  private func register(
    on server: Server,
    catalogue: ToolCatalogue,
    caller: ToolCaller,
    calls: RunningCalls,
    arguments: ToolCallArguments,
  ) async {
    let tools = catalogue.tools

    await server.withMethodHandler(ListTools.self) { _ in
      ListTools.Result(tools: tools)
    }

    await server.withMethodHandler(CallTool.self) { read in
      // What the host wrote, not what the SDK made of it.
      let parameters = await CallTool.Parameters(
        name: read.name,
        arguments: arguments.arguments(read: read.arguments),
        meta: read._meta,
      )
      let answer = await calls.run {
        do throws(ToolCallError) {
          return try await .success(caller.call(parameters))
        } catch {
          return .failure(error)
        }
      }

      switch answer {
      case let .success(result):
        return result
      case let .failure(.unknownTool(name)):
        // Not a call of any tool: a protocol error, the one kind of failure that is not a result.
        throw MCPError.invalidParams("Unknown tool: \(name)")
      case .failure(.cancelled):
        // A cancelled request is not answered; the server drops it when this is thrown.
        throw CancellationError()
      }
    }
  }
}
