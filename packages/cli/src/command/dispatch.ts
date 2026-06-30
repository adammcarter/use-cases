import { parseFlags } from "../args/parse.js";
import { renderEnvelope } from "../render.js";
import type { CliCommand } from "./types.js";

// Find the command whose token path is the longest prefix of argv. Two-token
// paths (e.g. ["matrix","validate"]) win over a one-token group, so a registered
// leaf is matched precisely; unmatched argv returns null and the caller falls
// through to the legacy dispatcher.
export function matchCommand(commands: readonly CliCommand[], argv: string[]): CliCommand | null {
  let best: CliCommand | null = null;
  for (const command of commands) {
    if (command.path.length > argv.length) {
      continue;
    }
    if (!command.path.every((token, index) => argv[index] === token)) {
      continue;
    }
    if (best === null || command.path.length > best.path.length) {
      best = command;
    }
  }
  return best;
}

// Run a matched registry command: parse its flags, invoke the handler, render
// the returned envelope (JSON or human per `json`), and return the exit code.
// Output happens HERE, never in the handler, so rendering stays centralized and
// byte-identical with the legacy path.
export function runRegistryCommand(command: CliCommand, argv: string[], json: boolean): number {
  const flags = parseFlags(argv, command.flags);
  const { envelope, exitCode } = command.handler({ argv, flags, json });
  process.stdout.write(renderEnvelope(envelope, json));
  return exitCode;
}
