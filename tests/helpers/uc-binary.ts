// The one place a black-box test learns where the binary is.
//
// Ladder row 2 of ADR 0007 builds an oracle suite that talks ONLY to the CLI
// and MCP, so that the Swift rewrite can be held to it unchanged. That is only
// possible if no test hardcodes how the binary is launched. `UC_BIN` is that
// seam: unset, it runs the built Node CLI; set, it runs whatever it names —
// which at ladder row 4 is the Swift build.
//
// Two older seams exist in this repo and are deliberately not repeated here:
// packing tarballs with `pnpm pack` (npm-shaped, and npm was removed in 0.7.0)
// and spawning `node packages/cli/dist/index.js` inline. Neither can be pointed
// at a non-Node binary.
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { resolve } from "node:path";

const repoRoot = resolve(import.meta.dirname, "../..");

/** Where the CLI under test lives, as a command plus any leading arguments. */
export interface UcBinary {
  command: string;
  leadingArgs: string[];
  /** True when UC_BIN named it, i.e. we are NOT testing the Node build. */
  overridden: boolean;
}

export function ucBinary(): UcBinary {
  const override = process.env.UC_BIN?.trim();
  if (override) {
    return { command: override, leadingArgs: [], overridden: true };
  }
  return {
    command: process.execPath,
    leadingArgs: [resolve(repoRoot, "packages/cli/dist/index.js")],
    overridden: false
  };
}

export interface RunOptions {
  cwd?: string;
  env?: Record<string, string>;
}

/** Run the CLI and hand back the raw result. Never throws on a nonzero exit. */
export function runUc(args: string[], options: RunOptions = {}): SpawnSyncReturns<string> {
  const binary = ucBinary();
  return spawnSync(binary.command, [...binary.leadingArgs, ...args], {
    cwd: options.cwd ?? repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...options.env }
  });
}

/** The v1 result envelope every `--json` command emits. */
export interface UcEnvelope<T = Record<string, unknown>> {
  schema_version: number;
  protocol_version: number;
  command: string;
  ok: boolean;
  complete: boolean;
  data: T;
  diagnostics: Array<Record<string, unknown>>;
  context: Record<string, unknown>;
}

export interface JsonResult<T = Record<string, unknown>> {
  envelope: UcEnvelope<T>;
  status: number;
  stdout: string;
  stderr: string;
}

/**
 * Run the CLI with `--json` and parse the envelope.
 *
 * A nonzero exit is NOT an error here — plenty of behaviours under test are
 * refusals, and their exit code is part of what the scenario asserts. Only
 * unparseable stdout throws, and it throws with the stderr attached, because a
 * bare "Unexpected token" tells the reader nothing about which command broke.
 */
export function runUcJson<T = Record<string, unknown>>(
  args: string[],
  options: RunOptions = {}
): JsonResult<T> {
  const result = runUc([...args, "--json"], options);
  const stdout = result.stdout ?? "";
  let envelope: UcEnvelope<T>;
  try {
    envelope = JSON.parse(stdout) as UcEnvelope<T>;
  } catch (error) {
    throw new Error(
      [
        `uc ${args.join(" ")} --json: stdout did not parse as JSON (exit ${result.status})`,
        `parse error: ${(error as Error).message}`,
        `stdout: ${stdout || "(empty)"}`,
        `stderr: ${result.stderr || "(empty)"}`
      ].join("\n")
    );
  }
  return { envelope, status: result.status ?? -1, stdout, stderr: result.stderr ?? "" };
}
