// MECHANICAL SEAMLESS-UPGRADE PROOF: 0.4.3 -> 0.5.0.
//
// `tests/fixtures/backcompat/contract-0.4.3.json` is the CLI's JSON contract as
// captured from the REAL 0.4.3 binary (built from the `release: v0.4.3` commit):
// every key path, its type, its value, and the process exit code, for each of the
// 16 steps of the daily loop over the fixed hermetic workspace.
//
// This test re-captures the same snapshot from the CURRENT build and asserts the
// current version is a strict SUPERSET of that contract — same rules as the 0.4.0
// contract test (no key removed, no type change, no array resize, no exit-code
// flip, no scalar change) — with ONE crucial difference:
//
//   THE DECLARED-CHANGES LIST IS EMPTY.
//
// 0.5.0 (variant parametrization) claims to be PURELY additive over 0.4.3. An
// empty exception list makes that claim mechanical: any behavioural difference a
// 0.4.3 consumer could observe — key, type, shape, value, or exit code — fails
// this test. Adding keys is allowed; that is what an additive release does.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const goldenPath = join(repoRoot, "tests/fixtures/backcompat/contract-0.4.3.json");
const capture = join(repoRoot, "scripts/capture-cli-contract.mjs");
const cliBin = join(repoRoot, "packages/cli/dist/index.js");

interface Entry {
  type: string;
  value: unknown;
}
interface Step {
  label: string;
  exit_code: number | null;
  keys: Record<string, Entry>;
}
interface Snapshot {
  steps: Step[];
}

let golden: Snapshot;
let current: Snapshot;

beforeAll(() => {
  // Build only when dist is absent (parallel suites share dist/ — see the 0.4.0
  // contract test for why an unconditional build races).
  if (!existsSync(cliBin)) {
    const build = spawnSync("corepack", ["pnpm", "build"], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    });
    if (build.status !== 0) {
      throw new Error(build.stderr || build.stdout);
    }
  }
  const result = spawnSync("node", [capture, cliBin], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(`contract capture failed (${result.status}): ${result.stderr}`);
  }
  golden = JSON.parse(readFileSync(goldenPath, "utf8")) as Snapshot;
  current = JSON.parse(result.stdout) as Snapshot;
}, 180_000);

function stepOf(snapshot: Snapshot, label: string): Step | undefined {
  return snapshot.steps.find((step) => step.label === label);
}

describe("0.5.0 is a strict superset of the 0.4.3 contract — no exceptions", () => {
  test("every step the 0.4.3 contract covers still exists", () => {
    const missing = golden.steps
      .map((step) => step.label)
      .filter((label) => stepOf(current, label) === undefined);
    expect(missing, "a command covered by the 0.4.3 contract disappeared").toEqual([]);
  });

  test("no key path was removed", () => {
    const removed: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const path of Object.keys(step.keys)) {
        if (!(path in now.keys)) {
          removed.push(`${step.label} ${path}`);
        }
      }
    }
    expect(removed, "a consumer reading these would now get undefined").toEqual([]);
  });

  test("no object lost a key, and no array changed length", () => {
    const shrunk: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const [path, before] of Object.entries(step.keys)) {
        const after = now.keys[path];
        if (!after || after.type !== before.type) continue;
        if (before.type === "object") {
          const had = String(before.value).split(",").filter(Boolean);
          const has = new Set(String(after.value).split(",").filter(Boolean));
          const gone = had.filter((key) => !has.has(key));
          if (gone.length > 0) {
            shrunk.push(`${step.label} ${path} lost {${gone.join(", ")}}`);
          }
        } else if (before.type === "array" && before.value !== after.value) {
          shrunk.push(`${step.label} ${path}: ${before.value} -> ${after.value}`);
        }
      }
    }
    expect(shrunk, "removing an object key or resizing an array breaks consumers").toEqual([]);
  });

  test("no type changed", () => {
    const retyped: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const [path, before] of Object.entries(step.keys)) {
        const after = now.keys[path];
        if (!after || after.type === before.type) continue;
        retyped.push(`${step.label} ${path}: ${before.type} -> ${after.type}`);
      }
    }
    expect(retyped, "a type change breaks a consumer's parse — nothing is declared for 0.5.0").toEqual([]);
  });

  test("no exit code changed", () => {
    const flipped: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      if (now.exit_code !== step.exit_code) {
        flipped.push(`${step.label}: ${step.exit_code} -> ${now.exit_code}`);
      }
    }
    expect(flipped, "an exit-code change flips an existing CI gate").toEqual([]);
  });

  test("no scalar value changed", () => {
    const changed: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const [path, before] of Object.entries(step.keys)) {
        const after = now.keys[path];
        if (!after || after.type !== before.type) continue;
        if (before.type === "object" || before.type === "array") continue;
        if (JSON.stringify(after.value) === JSON.stringify(before.value)) continue;
        changed.push(
          `${step.label} ${path}: ${JSON.stringify(before.value)} -> ${JSON.stringify(after.value)}`
        );
      }
    }
    expect(
      changed,
      "0.5.0 declares ZERO behavioural changes over 0.4.3 — any scalar drift is a break"
    ).toEqual([]);
  });
});
