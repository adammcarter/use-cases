import Foundation
import UseCasesCore

/// `schema list` and `schema validate-fixtures`
/// (packages/cli/src/commands/schema.ts). Both exit 0; a fixture that fails
/// validation says so in the envelope.
enum SchemaCommands {
  /// The bundled workspace `schema validate-fixtures` reaches for when the
  /// caller names none. It moved with the directory: `tests/` held nothing but
  /// fixture data after row 10d deleted the TypeScript suite, so it is now
  /// `fixtures/`. A default filesystem path is not part of ADR 0007 decision
  /// 8's freeze — that covers the envelope, the schemas, the marker syntax and
  /// the ledger formats — so the string moves and the recorded outputs that
  /// echo it move with it.
  static let defaultFixture = "fixtures/workspaces/minimal-valid"

  static let all = [list, validateFixtures]

  static let list = CommandSpecification(
    path: ["schema", "list"],
    command: "schema.list",
    summary: "List the public schema ids.",
    flags: [CommonFlags.json],
  ) { _ throws(CommandFailure) in
    let schemas = SchemaRegistry.publicSchemaIdentifiers.map { identifier in
      JSONValue.object(JSONObject([("id", .string(identifier))]))
    }
    let result = CliResult.make(
      command: "schema.list",
      data: .object(JSONObject([("schemas", .array(schemas))])),
    )
    return CommandOutput(result: result, exitCode: 0)
  }

  static let validateFixtures = CommandSpecification(
    path: ["schema", "validate-fixtures"],
    command: "schema.validate-fixtures",
    summary: "Validate the bundled fixtures against the published schemas.",
    flags: [
      FlagSpecification(
        key: "fixture",
        name: "--fixture",
        kind: .string,
        summary: "Path to the fixture directory to validate.",
        valueName: "<path>",
      ),
      CommonFlags.json,
    ],
  ) { context throws(CommandFailure) in
    var fixture = defaultFixture
    if case let .string(value) = context.flags["fixture"] {
      fixture = value
    }
    let fixturePath = WorkspacePath.absolute(
      fixture,
      relativeTo: FileManager.default.currentDirectoryPath,
    )
    let validation = try FixtureWorkspaceValidator.validate(
      workspacePath: fixturePath,
      registry: SchemaRegistryLoader.load(),
    )
    let result = CliResult.make(
      command: "schema.validate-fixtures",
      data: validation.envelopeData(fixture: fixture),
      isSuccessful: validation.isValid,
      isComplete: validation.isComplete,
      diagnostics: validation.diagnostics,
      dataRoot: fixturePath,
    )
    return CommandOutput(result: result, exitCode: 0)
  }
}
