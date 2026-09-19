import UseCasesCore

/// A path a caller supplied, bound to the workspace before it is opened
/// (packages/cli/src/runtime.ts `containedPathOrError`).
///
/// An escape is the stable `UCM_PATH_ESCAPE` envelope with exit 4; any other
/// failure is left to the caller, as the TypeScript rethrows it.
enum ContainedPath {
  case resolved(String)
  case refused(CommandOutput)

  static func resolve(
    command: String,
    workspaceRoot: String,
    candidate: String,
  ) -> ContainedPath {
    do throws(PathError) {
      return try .resolved(PathContainment.resolveContained(
        root: workspaceRoot,
        candidate: candidate,
      ))
    } catch {
      return .refused(CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: PublicErrorCode.pathEscape.rawValue,
          message: error.message,
        ),
        exitCode: 4,
      ))
    }
  }
}
