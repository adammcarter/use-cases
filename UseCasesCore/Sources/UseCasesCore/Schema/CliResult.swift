import Foundation

/// The result envelope every command returns. Its eight keys, their order and
/// their spellings are frozen contract (ADR 0007 decision 8).
///
/// `data` is a ``JSONValue`` rather than a generic `Encodable` for one reason:
/// the envelope has to come out byte for byte like the TypeScript's, and
/// Foundation's encoder loses key order. Everything on the wire is therefore
/// built as an ordered value and written by ``JSONWriter``.
///
/// The workspace snapshot carries placeholder values until the row that teaches
/// the CLI to read git; they are reproduced here exactly as the TypeScript
/// writes them, down to the epoch timestamp.
public struct CliResult: Sendable, Equatable {
  public let schemaVersion: Int
  public let protocolVersion: Int
  public let command: String
  public let isSuccessful: Bool
  public let isComplete: Bool
  public let data: JSONValue
  public let diagnostics: [Diagnostic]
  public let context: CliContext

  /// Build an envelope, defaulting the roots and identity the way the
  /// TypeScript factory does.
  ///
  /// An error-severity diagnostic always means the command did not succeed, so
  /// `ok` is false regardless of what the caller asked for.
  public static func make(
    command: String,
    data: JSONValue,
    isSuccessful: Bool = true,
    isComplete: Bool = true,
    diagnostics: [Diagnostic] = [],
    workspaceRoot: String? = nil,
    dataRoot: String? = nil,
    componentIdentifier: String? = nil,
  ) -> CliResult {
    let resolvedWorkspaceRoot = workspaceRoot ?? FileManager.default.currentDirectoryPath
    let resolvedDataRoot = dataRoot ?? resolvedWorkspaceRoot
    let resolvedComponent = componentIdentifier ?? ProductVersion.defaultComponentIdentifier
    let hasError = diagnostics.contains { $0.severity == .error }

    return CliResult(
      schemaVersion: 1,
      protocolVersion: 1,
      command: command,
      isSuccessful: hasError ? false : isSuccessful,
      isComplete: isComplete,
      data: data,
      diagnostics: diagnostics,
      context: CliContext(
        workspaceRoot: resolvedWorkspaceRoot,
        dataRoot: resolvedDataRoot,
        componentIdentifier: resolvedComponent,
        workspaceSnapshot: WorkspaceSnapshot(
          repositoryIdentifier: "unknown",
          versionControlSystem: "unknown",
          headRevision: "unknown",
          isDirty: false,
          workingTreeDigest:
          "sha256:0000000000000000000000000000000000000000000000000000000000000000",
          componentIdentifier: resolvedComponent,
          capturedAt: "1970-01-01T00:00:00.000Z",
        ),
      ),
    )
  }

  /// The envelope as a JSON value, in the frozen key order.
  public func jsonValue() -> JSONValue {
    .object(JSONObject([
      ("schema_version", .number(Double(schemaVersion))),
      ("protocol_version", .number(Double(protocolVersion))),
      ("command", .string(command)),
      ("ok", .bool(isSuccessful)),
      ("complete", .bool(isComplete)),
      ("data", data),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
      ("context", context.jsonValue),
    ]))
  }

  /// The envelope as wire JSON.
  public func jsonText() -> String {
    JSONWriter.encode(jsonValue())
  }
}
