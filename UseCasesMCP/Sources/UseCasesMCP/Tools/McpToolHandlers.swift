import Foundation
import UseCasesCore

/// The tool handlers (packages/mcp/src/toolHandlers.ts).
///
/// Every one of them resolves a workspace, calls the SAME read-only or
/// mutating core the CLI calls, and wraps the answer in the v1 envelope. None
/// of them decides anything itself: if the wrapper had its own logic the two
/// surfaces would drift, and the oracle compares them.
///
/// The families are split across extensions: matrix here, evidence in
/// `+Evidence.swift`, plans and capsules in `+Presentation.swift`, the showcase
/// verbs in `+Showcase.swift` and `+Approval.swift`.
public enum McpToolHandlers {
  /// `envelope`: the standard wrapper, with the workspace's roots on it and
  /// `ok`/`complete` true unless the caller says otherwise.
  static func envelope(
    _ command: String,
    _ data: JSONValue,
    _ workspace: ResolvedWorkspaceContext,
    isSuccessful: Bool = true,
    isComplete: Bool = true,
    diagnostics: [Diagnostic] = [],
  ) -> CliResult {
    CliResult.make(
      command: command,
      data: data,
      isSuccessful: isSuccessful,
      isComplete: isComplete,
      diagnostics: diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
  }

  /// SECURITY: refuse a caller-supplied id that is not canonical before it can
  /// become a filesystem path segment or a ledger lookup key. Nil when safe.
  static func unsafeIdentifier(
    _ command: String,
    _ parameterName: String,
    _ value: String,
    _ environment: McpEnvironment,
  ) -> CliResult? {
    guard !CanonicalIdentifier.isValid(value) else {
      return nil
    }
    return McpErrorEnvelope.make(
      command: command,
      code: "UCM_INVALID_ID",
      message: "Invalid \(parameterName) '\(value)': must be a canonical id "
        + "(lowercase, no path separators, no '..').",
      environment: environment,
    )
  }

  /// SECURITY: bound a caller-supplied file path to the workspace, symlink-safe,
  /// BEFORE it is read from disk.
  static func containedPath(
    _ command: String,
    workspaceRoot: String,
    candidate: String,
    environment: McpEnvironment,
  ) -> ContainedPath {
    do throws(PathError) {
      return try .resolved(PathContainment.resolveContained(
        root: workspaceRoot,
        candidate: candidate,
      ))
    } catch {
      return .refused(McpErrorEnvelope.make(
        command: command,
        code: PublicErrorCode.pathEscape.rawValue,
        message: error.message,
        environment: environment,
      ))
    }
  }

  /// A path bound to the workspace, or the refusal that stands in for it.
  enum ContainedPath {
    case resolved(String)
    case refused(CliResult)
  }

  static func matrix(_ workspace: ResolvedWorkspaceContext) throws(McpToolFailure)
    -> MatrixSnapshot
  {
    let registry = try McpSchemaRegistry.load()
    do throws(UseCaseMatrixError) {
      return try UseCaseMatrixLoader.load(context: workspace, registry: registry)
    } catch {
      throw McpToolFailure(error)
    }
  }

  static func evidence(_ workspace: ResolvedWorkspaceContext) throws(McpToolFailure)
    -> EvidenceSnapshot
  {
    do throws(EvidenceEventError) {
      return try EvidenceReplay.replay(context: workspace)
    } catch {
      throw McpToolFailure(error)
    }
  }

  // MARK: - doctor

  /// `doctor_roots`: the resolved roots, their provenance, and whether the data
  /// root can be written — the same probe the CLI's `doctor roots` makes, so
  /// both transports report the same `writable`.
  public static func doctorRoots(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "doctor.roots"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    let provenance = JSONValue.object(JSONObject([
      ("workspace_root", .string(workspace.provenance.workspaceRoot.rawValue)),
      ("data_root", .string(workspace.provenance.dataRoot.rawValue)),
      ("use_cases_root", .string(workspace.provenance.useCasesRoot.rawValue)),
      ("component_id", .string(workspace.provenance.componentIdentifier.rawValue)),
    ]))
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("workspace_root", .string(workspace.workspaceRoot)),
      ("data_root", .string(workspace.dataRoot)),
      ("use_cases_root", .string(workspace.useCasesRoot)),
      ("component_id", .string(workspace.componentIdentifier)),
      ("config_path", workspace.configPath.map(JSONValue.string) ?? .null),
      ("provenance", provenance),
      ("writable", .bool(access(workspace.dataRoot, W_OK) == 0)),
    ]))
    return envelope(command, data, workspace)
  }

  // MARK: - matrix

  public static func matrixValidate(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "matrix.validate"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try matrix(workspace)
    return envelope(
      command,
      snapshot.validationResult(),
      workspace,
      isSuccessful: true,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
    )
  }

  public static func matrixList(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "matrix.list"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try matrix(workspace)
    let selected = snapshot.queryUseCases(UseCaseQuery(
      valueTiers: McpToolArguments.strings(arguments, "value"),
      journeyRoles: McpToolArguments.strings(arguments, "journey_role"),
      lifecycles: McpToolArguments.strings(arguments, "lifecycle"),
      hostSurfaces: McpToolArguments.strings(arguments, "host"),
      tagsAny: McpToolArguments.strings(arguments, "tag"),
      changedPaths: McpToolArguments.strings(arguments, "changed_path"),
    ))
    // `strict` asks for the matrix's completeness to decide `ok`; without it an
    // incomplete matrix is still a successful listing.
    let isSuccessful = McpToolArguments.boolean(arguments, "strict") ? snapshot.isComplete : true
    return envelope(
      command,
      snapshot.listResult(for: selected),
      workspace,
      isSuccessful: isSuccessful,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
    )
  }

  public static func matrixStatus(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "matrix.status"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    let matrixSnapshot = try matrix(workspace)
    let evidenceSnapshot = try evidence(workspace)
    let isComplete = matrixSnapshot.isComplete && evidenceSnapshot.isComplete
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("matrix", matrixSnapshot.validationResult()),
      ("evidence", evidenceSnapshot.statusResult()),
    ]))
    return envelope(
      command,
      data,
      workspace,
      isSuccessful: isComplete,
      isComplete: isComplete,
      diagnostics: matrixSnapshot.diagnostics + evidenceSnapshot.diagnostics,
    )
  }
}
