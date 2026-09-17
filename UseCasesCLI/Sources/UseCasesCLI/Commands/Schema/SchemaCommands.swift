import Foundation
import UseCasesCore

/// `schema list` and `schema validate-fixtures`
/// (packages/cli/src/commands/schema.ts). Both exit 0; a fixture that fails
/// validation says so in the envelope.
enum SchemaCommands {
  static let defaultFixture = "tests/fixtures/workspaces/minimal-valid"

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
