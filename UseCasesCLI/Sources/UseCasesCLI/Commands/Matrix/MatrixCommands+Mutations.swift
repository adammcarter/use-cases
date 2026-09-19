import Foundation
import UseCasesCore

/// `matrix upsert` and `matrix remove`: argument checks, then the core
/// mutator, then the shared result mapping (`mutationOutput`).
extension MatrixCommands {
  static func runUpsert(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "matrix.upsert"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let targetFile = truthy(context.flags["file"])
    let inlineJSON = truthy(context.flags["useCaseJson"])
    let useCaseFile = truthy(context.flags["useCaseFile"])
    guard let targetFile, inlineJSON != nil || useCaseFile != nil else {
      return invalidArguments(
        command,
        "Missing --file or one of --use-case-json / --use-case-file.",
      )
    }
    if inlineJSON != nil, useCaseFile != nil {
      return invalidArguments(command, "Use only one of --use-case-json or --use-case-file.")
    }

    let source: String
    switch readInput(useCaseFile: useCaseFile, inlineJSON: inlineJSON ?? "", command: command) {
    case let .refused(output):
      return output
    case let .read(text):
      source = text
    }

    let parsed: JSONValue
    do throws(SchemaError) {
      parsed = try JavaScriptPropertyOrder.reordered(JSONParser.parse(source))
    } catch {
      return refusal(command, "matrix.mutation_invalid_json", error.message)
    }

    let result = try mutate(UseCaseMutationOptions(
      context: workspace,
      operation: .upsert,
      targetFile: targetFile,
      useCase: useCaseObject(parsed),
      expectedSemanticHash: string(context.flags["expectedHash"]),
      actor: "agent",
    ))
    return mutationOutput(command: command, result: result, workspace: workspace)
  }

  static func runRemove(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "matrix.remove"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let identifier = truthy(context.flags["useCase"]),
          let reason = truthy(context.flags["reason"])
    else {
      return invalidArguments(command, "Missing --use-case or --reason.")
    }
    let result = try mutate(UseCaseMutationOptions(
      context: workspace,
      operation: .remove,
      useCaseIdentifier: identifier,
      expectedSemanticHash: string(context.flags["expectedHash"]),
      reason: reason,
      actor: "agent",
    ))
    return mutationOutput(command: command, result: result, workspace: workspace)
  }

  // MARK: - Helpers

  private enum Input {
    case read(String)
    case refused(CommandOutput)
  }

  /// The row's JSON text: `--use-case-file` read from the working directory,
  /// deliberately uncontained (a read-only, one-shot input, often from /tmp),
  /// else the inline text.
  private static func readInput(
    useCaseFile: String?,
    inlineJSON: String,
    command: String,
  ) -> Input {
    guard let useCaseFile else {
      return .read(inlineJSON)
    }
    let path = WorkspacePath.absolute(
      useCaseFile,
      relativeTo: FileManager.default.currentDirectoryPath,
    )
    do throws(FileAccessError) {
      return try .read(NodeFile.readText(atPath: path))
    } catch {
      return .refused(refusal(
        command,
        "matrix.use_case_file_unreadable",
        "Could not read --use-case-file: \(path)",
      ))
    }
  }

  private static func mutate(_ options: UseCaseMutationOptions) throws(CommandFailure)
    -> UseCaseMutationResult
  {
    let registry = try SchemaRegistryLoader.load()
    do throws(UseCaseMatrixError) {
      return try UseCaseMatrixMutator.mutate(options, registry: registry)
    } catch {
      throw CommandFailure(error)
    }
  }

  /// `ok` unless blocked; a blocked path escape exits 4, any other block 1.
  private static func mutationOutput(
    command: String,
    result: UseCaseMutationResult,
    workspace: ResolvedWorkspaceContext,
  ) -> CommandOutput {
    let isSuccessful = result.status != .blocked
    let envelope = CliResult.make(
      command: command,
      data: result.jsonValue,
      isSuccessful: isSuccessful,
      isComplete: isSuccessful,
      diagnostics: result.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    guard !isSuccessful else {
      return CommandOutput(result: envelope, exitCode: 0)
    }
    let isPathEscape = result.diagnostics.contains { diagnostic in
      diagnostic.code == "matrix.mutation_path_escape"
    }
    return CommandOutput(result: envelope, exitCode: isPathEscape ? 4 : 1)
  }

  /// What `JSON.parse` handed the mutator, as the mutator reads it: a falsy
  /// value is no use case at all; an array, string, non-zero number or `true`
  /// has no `id`, so it reads as an object without one.
  private static func useCaseObject(_ value: JSONValue) -> JSONObject? {
    switch value {
    case let .object(object):
      object
    case .null, .bool(false), .string(""):
      nil
    case let .number(number) where number == 0 || number.isNaN:
      nil
    default:
      JSONObject()
    }
  }

  /// A string flag's value, or nil when absent.
  private static func string(_ value: ParsedFlagValue?) -> String? {
    guard case let .string(text) = value else {
      return nil
    }
    return text
  }

  /// A string flag's value when JavaScript reads it as truthy: present and
  /// not empty.
  private static func truthy(_ value: ParsedFlagValue?) -> String? {
    guard let text = string(value), !text.isEmpty else {
      return nil
    }
    return text
  }

  private static func invalidArguments(
    _ command: String,
    _ message: String,
  ) -> CommandOutput {
    refusal(command, "cli_invalid_arguments", message)
  }

  private static func refusal(
    _ command: String,
    _ code: String,
    _ message: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(command: command, code: code, message: message),
      exitCode: 2,
    )
  }
}
