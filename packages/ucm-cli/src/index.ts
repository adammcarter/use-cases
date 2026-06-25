#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  PUBLIC_SCHEMA_IDS,
  createCliResult,
  getVersionInfo,
  validateFixtureWorkspace
} from "@presentation-skills/ucm-core";

export function runCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
  const wantsVersion = normalizedArgv.includes("--version") || normalizedArgv.includes("-v");
  const wantsJson = normalizedArgv.includes("--json");

  if (wantsVersion) {
    if (wantsJson) {
      process.stdout.write(`${JSON.stringify(createCliResult("version", getVersionInfo()))}\n`);
    } else {
      process.stdout.write(`${getVersionInfo().version}\n`);
    }
    return 0;
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "list" && wantsJson) {
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("schema.list", {
          schemas: PUBLIC_SCHEMA_IDS.map((id) => ({ id }))
        })
      )}\n`
    );
    return 0;
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "validate-fixtures" && wantsJson) {
    const fixture = valueAfter(normalizedArgv, "--fixture") ?? "tests/fixtures/workspaces/minimal-valid";
    const fixturePath = resolve(process.cwd(), fixture);
    const result = validateFixtureWorkspace(fixturePath);
    process.stdout.write(
      `${JSON.stringify(
        createCliResult(
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
        )
      )}\n`
    );
    return 0;
  }

  process.stderr.write(
    `${JSON.stringify(
      createCliResult(
        "unknown",
        {},
        {
          ok: false,
          complete: false,
          diagnostics: [
            {
              code: "command.unknown",
              severity: "error",
              message: "No supported P1 command was provided. Try --version --json or schema list --json.",
              source_path: null,
              json_pointer: null,
              entity_id: null,
              related_ids: []
            }
          ]
        }
      )
    )}\n`
  );
  return 2;
}

function valueAfter(argv: string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) {
    return undefined;
  }
  return argv[index + 1];
}

function isEntrypoint(): boolean {
  if (!process.argv[1]) {
    return false;
  }

  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntrypoint()) {
  process.exitCode = runCli(process.argv.slice(2));
}
