import Foundation
import UseCasesCore

/// The six repo-scoped resource views. Each returns the SAME envelope the
/// matching CLI command returns, so a host reading a resource and a host
/// running the command see one answer.
enum McpResourceViews {
  typealias View = @Sendable (ResolvedWorkspaceContext, McpEnvironment) throws(McpToolFailure)
    -> JSONValue

  static func view(for key: String) -> View? {
    switch key {
    case "matrix": matrix
    case "matrix/status": matrixStatus
    case "freshness": freshness
    case "bindings": bindings
    case "ledger": ledger
    case "evidence": evidence
    case "config": config
    default: nil
    }
  }

  /// No proof-signing key is configured for a read-only view, mirroring the
  /// CLI default (`uc scan` and `uc validate-ledger` without `--public-key`).
  private static let noKeyResolver: PublicKeyResolver = { _, _ in nil }

  private static func scanOptions(_ workspace: ResolvedWorkspaceContext) -> ScanCommandOptions {
    let paths = McpMarkerPaths(workspace)
    var options = ScanCommandOptions(
      context: workspace,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      policyMode: .feature,
      publicKeyResolver: noKeyResolver,
      generatedAt: McpClock.nowIsoString(),
    )
    options.trustedKeyConfigured = false
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    return options
  }

  private static let matrix: View = { workspace, _ throws(McpToolFailure) in
    let snapshot = try McpToolHandlers.matrix(workspace)
    let all = snapshot.queryUseCases(UseCaseQuery())
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("validation", snapshot.validationResult()),
      ("list", snapshot.listResult(for: all)),
    ]))
    return McpToolHandlers.envelope(
      "matrix.validate",
      data,
      workspace,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
    ).jsonValue()
  }

  private static let matrixStatus: View = { workspace, _ throws(McpToolFailure) in
    let snapshot = try McpToolHandlers.matrix(workspace)
    let evidence = try McpToolHandlers.evidence(workspace)
    let isComplete = snapshot.isComplete && evidence.isComplete
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("matrix", snapshot.validationResult()),
      ("evidence", evidence.statusResult()),
    ]))
    return McpToolHandlers.envelope(
      "matrix.status",
      data,
      workspace,
      isSuccessful: isComplete,
      isComplete: isComplete,
      diagnostics: snapshot.diagnostics + evidence.diagnostics,
    ).jsonValue()
  }

  private static let freshness: View = { workspace, environment throws(McpToolFailure) in
    let registry = try McpSchemaRegistry.load()
    let result: ScanCommandResult
    do throws(MarkerCommandError) {
      result = try ScanCommand.run(
        scanOptions(workspace),
        registry: registry,
        gitRunner: GitProcessRunner(environment: environment.variables),
      )
    } catch {
      throw McpToolFailure(error)
    }
    return McpToolHandlers.envelope(
      "markers.scan",
      result.jsonValue,
      workspace,
      isSuccessful: result.exitCode == 0,
      isComplete: result.exitCode == 0,
    ).jsonValue()
  }

  private static let bindings: View = { workspace, environment throws(McpToolFailure) in
    let registry = try McpSchemaRegistry.load()
    let prepared: ScanPreparation
    do throws(MarkerCommandError) {
      prepared = try ScanCommand.prepare(
        scanOptions(workspace),
        registry: registry,
        gitRunner: GitProcessRunner(environment: environment.variables),
      )
    } catch {
      throw McpToolFailure(error)
    }
    let rows = prepared.registry.rowToSlugs
      .map { entry in
        (identifier: entry.rowIdentifier, slugs: entry.bindingSlugs.sorted())
      }
      .sorted { left, right in
        McpLocaleOrder.isAscending(left.identifier, right.identifier)
      }
      .map { entry in
        JSONValue.object(JSONObject([
          ("row_id", .string(entry.identifier)),
          ("binding_slugs", .array(entry.slugs.map(JSONValue.string))),
        ]))
      }
    let slugs = prepared.registry.slugToRow
      .sorted { left, right in
        McpLocaleOrder.isAscending(left.bindingSlug, right.bindingSlug)
      }
      .map { entry in
        JSONValue.object(JSONObject([
          ("slug", .string(entry.bindingSlug)),
          ("row_id", .string(entry.rowIdentifier)),
        ]))
      }
    let isValid = prepared.registryErrors.isEmpty
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("registry_valid", .bool(isValid)),
      ("rows", .array(rows)),
      ("slugs", .array(slugs)),
      ("registry_errors", .array(prepared.registryErrors.map(\.jsonValue))),
    ]))
    return McpToolHandlers.envelope(
      "markers.bindings",
      data,
      workspace,
      isSuccessful: isValid,
      isComplete: isValid,
    ).jsonValue()
  }

  private static let ledger: View = { workspace, environment throws(McpToolFailure) in
    let paths = McpMarkerPaths(workspace)
    let registry = try McpSchemaRegistry.load()
    var options = ValidateLedgerCommandOptions(
      context: workspace,
      evidencePath: paths.evidencePath,
      bindingsPath: paths.bindingsPath,
      publicKeyResolver: noKeyResolver,
    )
    options.repositoryWorkingDirectory = workspace.workspaceRoot
    let result: ValidateLedgerCommandResult
    do throws(MarkerCommandError) {
      result = try ValidateLedgerCommand.run(
        options,
        registry: registry,
        gitRunner: GitProcessRunner(environment: environment.variables),
      )
    } catch {
      throw McpToolFailure(error)
    }
    return McpToolHandlers.envelope(
      "markers.validate-ledger",
      result.jsonValue,
      workspace,
      isSuccessful: result.isOK,
      isComplete: result.isOK,
    ).jsonValue()
  }

  private static let evidence: View = { workspace, _ throws(McpToolFailure) in
    let snapshot = try McpToolHandlers.evidence(workspace)
    return McpToolHandlers.envelope(
      "evidence.status",
      snapshot.statusResult(),
      workspace,
      isSuccessful: snapshot.isComplete,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
    ).jsonValue()
  }

  /// The roots and their provenance, without the `writable` probe the
  /// `doctor_roots` TOOL makes: a resource only reports, it does not test
  /// whether it could write.
  private static let config: View = { workspace, _ throws(McpToolFailure) in
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
    ]))
    return McpToolHandlers.envelope(
      "doctor.roots",
      data,
      workspace,
      diagnostics: workspace.diagnostics,
    ).jsonValue()
  }
}
