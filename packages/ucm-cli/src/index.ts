#!/usr/bin/env node
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { getVersionInfo } from "@presentation-skills/ucm-core";

type CliEnvelope<T> = {
  ok: boolean;
  command: string;
  schema_version: 1;
  data?: T;
  warnings: string[];
  errors: string[];
};

function envelope<T>(command: string, data: T): CliEnvelope<T> {
  return {
    ok: true,
    command,
    schema_version: 1,
    data,
    warnings: [],
    errors: []
  };
}

export function runCli(argv: string[]): number {
  const wantsVersion = argv.includes("--version") || argv.includes("-v");
  const wantsJson = argv.includes("--json");

  if (wantsVersion) {
    if (wantsJson) {
      process.stdout.write(`${JSON.stringify(envelope("version", getVersionInfo()))}\n`);
    } else {
      process.stdout.write(`${getVersionInfo().version}\n`);
    }
    return 0;
  }

  const error: CliEnvelope<never> = {
    ok: false,
    command: "unknown",
    schema_version: 1,
    warnings: [],
    errors: ["No P0 command was provided. Try --version --json."]
  };
  process.stderr.write(`${JSON.stringify(error)}\n`);
  return 2;
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
