import { describe, expect, test } from "vitest";
import {
  VERIFIER_PRESET_IDS,
  expandPreset,
  isVerifierPresetId
} from "../../src/markers/index.js";

const SLUG = "presentation_skills.evidence.crash_durable_ledger_writes";

describe("verifier presets", () => {
  test("ships the documented preset id union", () => {
    expect([...VERIFIER_PRESET_IDS].sort()).toEqual(
      [
        "command.generic",
        "go.test",
        "js.npm-test",
        "js.vitest",
        "make.target",
        "python.pytest"
      ].sort()
    );
  });

  test("js.vitest runs the locally-installed vitest without a global pnpm, {slug} substituted", () => {
    const res = expandPreset("js.vitest", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "js.vitest",
      expansion: {
        kind: "script",
        command: ["npx", "--no-install", "vitest", "run", `tests/use-cases/${SLUG}.test.ts`],
        inputs: [`tests/use-cases/${SLUG}.test.ts`]
      }
    });
  });

  test("js.vitest command shape does not hard-depend on a global pnpm", () => {
    const res = expandPreset("js.vitest", SLUG);
    expect(res.status).toBe("resolved");
    if (res.status === "resolved") {
      // The launcher must resolve a locally-installed vitest so npm-only
      // machines (no global pnpm) do not fail at spawn.
      expect(res.expansion.command[0]).not.toBe("pnpm");
      expect(res.expansion.command).not.toContain("pnpm");
    }
  });

  test("js.npm-test expands to npm test with no inputs", () => {
    const res = expandPreset("js.npm-test", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "js.npm-test",
      expansion: { kind: "script", command: ["npm", "test"], inputs: [] }
    });
  });

  test("python.pytest substitutes {slug} into command and inputs the test file", () => {
    const res = expandPreset("python.pytest", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "python.pytest",
      expansion: {
        kind: "script",
        command: ["pytest", `tests/use_cases/${SLUG}_test.py`],
        inputs: [`tests/use_cases/${SLUG}_test.py`]
      }
    });
  });

  test("go.test expands to go test ./... with no inputs", () => {
    const res = expandPreset("go.test", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "go.test",
      expansion: { kind: "script", command: ["go", "test", "./..."], inputs: [] }
    });
  });

  test("make.target substitutes {slug} into the SLUG argument", () => {
    const res = expandPreset("make.target", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "make.target",
      expansion: {
        kind: "script",
        command: ["make", "test-use-case", `SLUG=${SLUG}`],
        inputs: []
      }
    });
  });

  test("command.generic has no default command — caller supplies argv", () => {
    const res = expandPreset("command.generic", SLUG);
    expect(res).toEqual({
      status: "resolved",
      preset: "command.generic",
      expansion: { kind: "script", command: [], inputs: [] }
    });
  });

  test("an unknown preset id is returned blocked, not thrown", () => {
    const res = expandPreset("ruby.rspec", SLUG);
    expect(res.status).toBe("blocked");
    if (res.status === "blocked") {
      expect(res.reason).toMatch(/unknown verifier preset/i);
      expect(res.reason).toContain("ruby.rspec");
    }
  });

  test("isVerifierPresetId narrows known + rejects unknown ids", () => {
    expect(isVerifierPresetId("js.vitest")).toBe(true);
    expect(isVerifierPresetId("command.generic")).toBe(true);
    expect(isVerifierPresetId("ruby.rspec")).toBe(false);
    expect(isVerifierPresetId(42)).toBe(false);
    expect(isVerifierPresetId(undefined)).toBe(false);
  });
});
