import Foundation
import UseCasesCore

/// `bind`, `unbind` and `rebind`: argument checks, then the core command, its
/// result as the envelope's data and its exit code as the process's.
extension MarkersCommands {
  static func runBind(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.bind"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    // --register-existing registers a marker span already in the source, so
    // it implies explicit when no mode is given.
    let modeText = runtime.string("mode") ?? (runtime.isOn("registerExisting") ? "explicit" : nil)
    guard let row = runtime.truthy("row"), let file = runtime.truthy("file"),
          let mode = modeText.flatMap(MarkerMode.init(rawValue:))
    else {
      return invalidArguments(command, "Missing --row, --file, or --mode (explicit|swift-func).")
    }
    let paths = runtime.paths(workspace)
    var options = BindCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      rowIdentifier: row,
      file: file,
      mode: mode,
      clock: currentTimestamp,
      identifierFactory: MarkerEventIdentifier.generate,
    )
    options.suffix = runtime.string("suffix")
    options.line = runtime.integer("line")
    options.startLine = runtime.integer("startLine")
    options.endLine = runtime.integer("endLine")
    options.commentPrefix = runtime.string("commentPrefix")
    options.registerExisting = runtime.isOn("registerExisting")
    options.dryRun = runtime.isOn("dryRun")
    options.version = ProductVersion.version

    let registry = try SchemaRegistryLoader.load()
    let result: BindCommandResult
    do throws(MarkerCommandError) {
      result = try BindCommand.run(options, registry: registry)
    } catch {
      throw CommandFailure(error)
    }
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  static func runUnbind(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.unbind"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    guard let row = runtime.truthy("row") else {
      return invalidArguments(command, "Missing --row.")
    }
    let paths = runtime.paths(workspace)
    var options = UnbindCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      rowIdentifier: row,
      clock: currentTimestamp,
      identifierFactory: MarkerEventIdentifier.generate,
    )
    options.suffix = runtime.string("suffix")
    options.reason = runtime.string("reason")
    options.dryRun = runtime.isOn("dryRun")
    options.version = ProductVersion.version

    let registry = try SchemaRegistryLoader.load()
    let result: UnbindCommandResult
    do throws(MarkerCommandError) {
      result = try UnbindCommand.run(options, registry: registry)
    } catch {
      throw CommandFailure(error)
    }
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  static func runRebind(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.rebind"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }
    let runtime = MarkerRuntime(context: context)
    guard let row = runtime.truthy("row"), let file = runtime.truthy("file"),
          let mode = runtime.string("mode").flatMap(MarkerMode.init(rawValue:))
    else {
      return invalidArguments(command, "Missing --row, --file, or --mode (explicit|swift-func).")
    }
    let paths = runtime.paths(workspace)
    var options = RebindCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      rowIdentifier: row,
      file: file,
      mode: mode,
      clock: currentTimestamp,
      identifierFactory: MarkerEventIdentifier.generate,
    )
    options.suffix = runtime.string("suffix")
    options.line = runtime.integer("line")
    options.startLine = runtime.integer("startLine")
    options.endLine = runtime.integer("endLine")
    options.reason = runtime.string("reason")
    options.commentPrefix = runtime.string("commentPrefix")
    options.dryRun = runtime.isOn("dryRun")
    options.version = ProductVersion.version

    let registry = try SchemaRegistryLoader.load()
    let result: RebindCommandResult
    do throws(MarkerCommandError) {
      result = try RebindCommand.run(options, registry: registry)
    } catch {
      throw CommandFailure(error)
    }
    return MarkerOutput.make(
      command: command,
      result: result.jsonValue,
      exitCode: result.exitCode,
      isOK: result.exitCode == 0,
      workspace: workspace,
    )
  }

  /// `new Date().toISOString()`.
  static func currentTimestamp() -> String {
    let milliseconds = (Date().timeIntervalSince1970 * 1000).rounded(.down)
    return JavaScriptTimestamp.isoString(milliseconds: milliseconds)
  }

  /// The usage refusal every marker command shares: exit 2.
  static func invalidArguments(
    _ command: String,
    _ message: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(command: command, code: "cli_invalid_arguments", message: message),
      exitCode: 2,
    )
  }
}
