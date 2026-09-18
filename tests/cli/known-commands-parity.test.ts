import { describe, expect, test } from "vitest";
import { allCommands } from "../../packages/cli/src/command/registry.js";
import {
  KNOWN_CLI_COMMANDS,
  KNOWN_FLAT_CLI_COMMANDS,
  BUILTIN_FLAT_CLI_COMMANDS
} from "../../packages/core/src/cli/knownCommands.js";

// Skill and agent bodies are validated against these two sets: a body that tells
// its reader to run `use-cases <something>` is flagged when `<something>` is not a real
// command. That guard is only as good as the sets, and they used to be a
// hand-maintained copy of the CLI — so `use-cases impact` and `use-cases showcase
// request-approval` shipped for real while the validator still called them
// unknown. This test makes the copy impossible to drift: the sets must equal what
// the registry actually dispatches, plus the bespoke builtins that never entered
// it (version / init / help live in builtins.ts by design).
//: @use-case:agents.roster.command_allowlist_tracks_cli
describe("known CLI command sets track the real registry", () => {
  const registryPaths = allCommands.map((command) => command.path);
  const registryFlat = registryPaths.filter((path) => path.length === 1).map((path) => path[0]);
  const registryNested = registryPaths.filter((path) => path.length >= 2).map((path) => `${path[0]} ${path[1]}`);

  test("every dispatchable nested command is allowed in skill and agent bodies", () => {
    expect([...KNOWN_CLI_COMMANDS].sort()).toEqual([...new Set(registryNested)].sort());
  });

  test("every dispatchable flat command is allowed, plus the bespoke builtins", () => {
    const expected = [...new Set([...registryFlat, ...BUILTIN_FLAT_CLI_COMMANDS])].sort();
    expect([...KNOWN_FLAT_CLI_COMMANDS].sort()).toEqual(expected);
  });

  test("the commands that exposed the drift are now allowed", () => {
    expect(KNOWN_FLAT_CLI_COMMANDS.has("impact")).toBe(true);
    expect(KNOWN_CLI_COMMANDS.has("showcase request-approval")).toBe(true);
  });
});
//: @use-case:end agents.roster.command_allowlist_tracks_cli
