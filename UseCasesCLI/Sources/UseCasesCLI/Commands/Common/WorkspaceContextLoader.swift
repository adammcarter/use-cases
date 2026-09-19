import Foundation
import UseCasesCore

/// Resolves the workspace a command runs against from `--repo`, `--data-root`
/// and `--component` (packages/cli/src/runtime.ts `resolveContextOrError`).
///
/// A missing `--repo` is refused with exit 2 and a `--data-root` outside it
/// with exit 4, as envelopes; a config the resolver cannot accept is thrown, so
/// the dispatcher reports it with exit 1.
///
/// The plugin root is left to the core's default. Nothing observable reads it:
/// it is on no envelope, no `doctor` payload and no schema.
enum WorkspaceContextLoader {
  static func resolve(
    arguments: [String],
    command: String,
  ) throws(CommandFailure) -> ContextResolution {
    let workingDirectory = FileManager.default.currentDirectoryPath
    let workspaceRoot = WorkspacePath.absolute(
      ArgumentScanner.value(after: "--repo", in: arguments) ?? ".",
      relativeTo: workingDirectory,
    )
    if let missing = WorkspaceContextResolver.workspaceNotFoundDiagnostic(
      workspaceRoot: workspaceRoot,
    ) {
      return refusal(command: command, code: missing.code, message: missing.message, exitCode: 2)
    }

    let dataRootValue = ArgumentScanner.value(after: "--data-root", in: arguments)
    var dataRootOverride: String?
    if let dataRootValue, !dataRootValue.isEmpty {
      let dataRoot = WorkspacePath.absolute(dataRootValue, relativeTo: workingDirectory)
      guard WorkspacePath.isContained(root: workspaceRoot, child: dataRoot) else {
        return refusal(
          command: command,
          code: "unsafe_data_root",
          message: "--data-root must stay inside --repo.",
          exitCode: 4,
        )
      }
      dataRootOverride = dataRoot
    }

    return try .resolved(resolveContext(
      workspaceRoot: workspaceRoot,
      dataRootOverride: dataRootOverride,
      component: ArgumentScanner.value(after: "--component", in: arguments),
    ))
  }

  private static func resolveContext(
    workspaceRoot: String,
    dataRootOverride: String?,
    component: String?,
  ) throws(CommandFailure) -> ResolvedWorkspaceContext {
    let registry = try SchemaRegistryLoader.load()
    do {
      return try WorkspaceContextResolver.resolve(
        options: ResolveWorkspaceContextOptions(
          workspaceRoot: workspaceRoot,
          dataRootOverride: dataRootOverride,
          component: component,
        ),
        registry: registry,
      )
    } catch {
      throw CommandFailure(error)
    }
  }

  private static func refusal(
    command: String,
    code: String,
    message: String,
    exitCode: Int32,
  ) -> ContextResolution {
    .refused(CommandOutput(
      result: ErrorEnvelope.make(command: command, code: code, message: message),
      exitCode: exitCode,
    ))
  }
}
