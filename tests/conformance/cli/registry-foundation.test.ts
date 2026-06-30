import { describe, expect, test } from "vitest";
import { parseFlags } from "../../../packages/cli/src/args/parse.js";
import { matchCommand } from "../../../packages/cli/src/command/dispatch.js";
import type { CliCommand, FlagSpec } from "../../../packages/cli/src/command/types.js";

// The registry foundation must reproduce the legacy arg helpers EXACTLY, so a
// migrated command parses identically. These lock that contract.

const flags: FlagSpec[] = [
  { key: "json", name: "--json", kind: "boolean", summary: "" },
  { key: "repo", name: "--repo", kind: "string", summary: "", valueName: "<path>" },
  { key: "maxItems", name: "--max-items", kind: "integer", summary: "" },
  { key: "tag", name: "--tag", kind: "string", summary: "", repeatable: true }
];

describe("parseFlags mirrors the legacy valueAfter/valuesAfter/includes semantics", () => {
  test("boolean is presence-based (argv.includes)", () => {
    expect(parseFlags(["--json"], flags).json).toBe(true);
    expect(parseFlags([], flags).json).toBe(false);
  });

  test("string takes the token after the FIRST occurrence", () => {
    expect(parseFlags(["--repo", "/a", "--repo", "/b"], flags).repo).toBe("/a");
    expect(parseFlags([], flags).repo).toBeUndefined();
  });

  test("a value-bearing flag consumes the next token even if it looks like a flag", () => {
    // Legacy valueAfter does argv[index+1] unconditionally — preserve that.
    expect(parseFlags(["--repo", "--max-items"], flags).repo).toBe("--max-items");
  });

  test("integer is Number(valueAfter), finite or undefined", () => {
    expect(parseFlags(["--max-items", "3"], flags).maxItems).toBe(3);
    expect(parseFlags(["--max-items", "nope"], flags).maxItems).toBeUndefined();
    expect(parseFlags([], flags).maxItems).toBeUndefined();
  });

  test("repeatable collects every occurrence, or undefined when absent", () => {
    expect(parseFlags(["--tag", "a", "--tag", "b"], flags).tag).toEqual(["a", "b"]);
    expect(parseFlags([], flags).tag).toBeUndefined();
  });
});

describe("matchCommand resolves the longest path prefix", () => {
  const stub = (path: CliCommand["path"], command: string): CliCommand => ({
    path,
    command,
    summary: "",
    flags: [],
    handler: () => ({ envelope: {}, exitCode: 0 })
  });
  const commands = [stub(["matrix"], "matrix"), stub(["matrix", "validate"], "matrix.validate")];

  test("a two-token leaf wins over a one-token group", () => {
    expect(matchCommand(commands, ["matrix", "validate", "--repo", "."])?.command).toBe("matrix.validate");
  });

  test("falls back to the group when only it matches", () => {
    expect(matchCommand(commands, ["matrix", "list"])?.command).toBe("matrix");
  });

  test("no match returns null (caller falls through to legacy)", () => {
    expect(matchCommand(commands, ["showcase", "start"])).toBeNull();
    expect(matchCommand([], ["matrix", "validate"])).toBeNull();
  });
});
