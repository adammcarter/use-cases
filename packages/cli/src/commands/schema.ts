import { resolve } from "node:path";
import type { CliCommand } from "../command/types.js";
import { createCliResult, PUBLIC_SCHEMA_IDS, validateFixtureWorkspace } from "../runtime.js";
import { jsonFlag } from "./common.js";

// `schema list` — static catalog of public schema ids. Always exit 0.
export const schemaListCommand: CliCommand = {
  path: ["schema", "list"],
  command: "schema.list",
  summary: "List the public schema ids.",
  flags: [jsonFlag],
  handler: () => ({
    envelope: createCliResult("schema.list", { schemas: PUBLIC_SCHEMA_IDS.map((id) => ({ id })) }),
    exitCode: 0
  })
};

// `schema validate-fixtures` — validate bundled fixtures against published
// schemas. Validation result rides in the envelope (ok/diagnostics); exit 0.
export const schemaValidateFixturesCommand: CliCommand = {
  path: ["schema", "validate-fixtures"],
  command: "schema.validate-fixtures",
  summary: "Validate the bundled fixtures against the published schemas.",
  flags: [
    {
      key: "fixture",
      name: "--fixture",
      kind: "string",
      valueName: "<path>",
      summary: "Path to the fixture directory to validate."
    },
    jsonFlag
  ],
  handler: ({ flags }) => {
    const fixture = (flags.fixture as string | undefined) ?? "tests/fixtures/workspaces/minimal-valid";
    const fixturePath = resolve(process.cwd(), fixture);
    const result = validateFixtureWorkspace(fixturePath);
    return {
      envelope: createCliResult(
        "schema.validate-fixtures",
        {
          fixture,
          validated_schema_ids: result.validated_schema_ids,
          expected_state: result.expected_state
        },
        {
          ok: result.ok,
          complete: result.complete,
          diagnostics: result.diagnostics,
          dataRoot: fixturePath
        }
      ),
      exitCode: 0
    };
  }
};

export const schemaCommands: CliCommand[] = [schemaListCommand, schemaValidateFixturesCommand];
