import Foundation
import UseCasesCore

/// `doctor skills` and `doctor roots` (packages/cli/src/commands/doctor.ts).
enum DoctorCommands {
  static let all = [skills, roots]

  /// Hidden from help: a maintainer check that expects a plugin checkout.
  static let skills = CommandSpecification(
    path: ["doctor", "skills"],
    command: "doctor.skills",
    summary: "Validate packaged skill assets (maintainer-only; expects a plugin checkout).",
    flags: CommonFlags.workspace,
    isHidden: true,
  ) { context throws(CommandFailure) in
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(
      arguments: context.arguments,
      command: "doctor.skills",
    ) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let validation: SkillAssetValidationResult
    do throws(SkillAssetValidationError) {
      validation = try SkillAssetValidator.validate(context: workspace)
    } catch {
      throw CommandFailure(error)
    }
    let result = CliResult.make(
      command: "doctor.skills",
      data: validation.jsonValue,
      isSuccessful: validation.isComplete,
      isComplete: validation.isComplete,
      diagnostics: validation.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: validation.isComplete ? 0 : 1)
  }

  static let roots = CommandSpecification(
    path: ["doctor", "roots"],
    command: "doctor.roots",
    summary: "Report the resolved workspace and data roots.",
    flags: CommonFlags.workspace,
  ) { context throws(CommandFailure) in
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(
      arguments: context.arguments,
      command: "doctor.roots",
    ) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let result = CliResult.make(
      command: "doctor.roots",
      data: rootsData(workspace),
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  private static func rootsData(_ workspace: ResolvedWorkspaceContext) -> JSONValue {
    let provenance = JSONValue.object(JSONObject([
      ("workspace_root", .string(workspace.provenance.workspaceRoot.rawValue)),
      ("data_root", .string(workspace.provenance.dataRoot.rawValue)),
      ("use_cases_root", .string(workspace.provenance.useCasesRoot.rawValue)),
      ("component_id", .string(workspace.provenance.componentIdentifier.rawValue)),
    ]))
    return .object(JSONObject([
      ("schema_version", .number(1)),
      ("workspace_root", .string(workspace.workspaceRoot)),
      ("data_root", .string(workspace.dataRoot)),
      ("use_cases_root", .string(workspace.useCasesRoot)),
      ("component_id", .string(workspace.componentIdentifier)),
      ("config_path", workspace.configPath.map(JSONValue.string) ?? .null),
      ("provenance", provenance),
      ("writable", .bool(access(workspace.dataRoot, W_OK) == 0)),
    ]))
  }
}
