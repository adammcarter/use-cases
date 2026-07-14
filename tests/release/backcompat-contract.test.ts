// MECHANICAL NO-BREAKING-CHANGE PROOF.
//
// `tests/fixtures/backcompat/contract-0.4.0.json` is the CLI's JSON contract as
// captured from the PUBLISHED 0.4.0 binary: every key path, its type, its value,
// and the process exit code, for each step of the daily loop (validate -> bind ->
// scan -> verify -> scan) over a fixed hermetic workspace.
//
// This test re-captures the same snapshot from the CURRENT build and asserts the
// current version is a strict SUPERSET of that contract:
//
//   * no key path removed          -> a consumer reading it would get undefined
//   * no object key removed        -> same, one level up
//   * no type changed              -> a consumer's parse would break
//   * no array length changed      -> a consumer's index/iteration would break
//   * no exit code changed         -> a consumer's CI would flip
//   * no scalar value changed      -> UNLESS declared below, with a reason
//
// Adding keys is always allowed: that is what an additive release does.
//
// The declared list is the point. A behavioural change is not forbidden — it is
// forbidden to be SILENT. Anything that changes and is not declared fails here,
// so no future release can quietly alter the contract.
//
// Regenerate the golden ONLY when intentionally cutting a new baseline:
//   node scripts/capture-cli-contract.mjs "$PWD/packages/cli/dist/index.js" \
//     > tests/fixtures/backcompat/contract-<version>.json
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const goldenPath = join(repoRoot, "tests/fixtures/backcompat/contract-0.4.0.json");
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

// ---------------------------------------------------------------------------
// Every intentional difference from the 0.4.0 contract, with the reason. A
// difference NOT listed here is a breaking change and fails the test.
// ---------------------------------------------------------------------------
const DECLARED_CHANGES: { path: RegExp; reason: string }[] = [
  {
    // An UNBOUND row's required_action was null — the one status most likely to
    // need a next command, and the core never supplied one. Nothing branches on
    // the null (a consumer reading `required_action !== null` as "needs work" was
    // previously told an unbound row needed nothing), so this can only make a
    // consumer more correct.
    path: /^\$\.data\.status\.rows\[\d+\]\.required_action$/,
    reason: "UNBOUND rows now carry a bind command instead of null (0.4.1)"
  },
  {
    // THE DATA-LOSS FIX, captured by the golden itself. On 0.4.0, `verify --row X`
    // truncated the results ledger to only that row, so every OTHER row silently
    // lost its evidence and fell back to UNVERIFIED_LOCAL. The 0.4.0 snapshot
    // records that bug as its own behaviour. 0.4.1 merges instead, so the untouched
    // row keeps its VERIFIED_LOCAL. This is the whole point of the release.
    path: /^\$\.data\.status\.rows\[\d+\]\.local_status$/,
    reason: "verify --row no longer destroys other rows' evidence (0.4.1 data-loss fix)"
  }
];

function isDeclared(path: string): string | null {
  return DECLARED_CHANGES.find((change) => change.path.test(path))?.reason ?? null;
}

let golden: Snapshot;
let current: Snapshot;

beforeAll(() => {
  // Build ONLY when dist is absent. CI (and any sane local run) builds before the
  // suite, and vitest runs files in parallel — so an unconditional `pnpm build`
  // here races other suites' builds on the same dist/ output, and a momentarily
  // half-written CLI makes UNRELATED tests fail. Build defensively, not eagerly.
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

describe("the 0.4.0 JSON contract still holds", () => {
  test("every step the 0.4.0 contract covers still exists", () => {
    const missing = golden.steps
      .map((step) => step.label)
      .filter((label) => stepOf(current, label) === undefined);
    expect(missing, "a command covered by the 0.4.0 contract disappeared").toEqual([]);
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

  test("no type changed, unless declared", () => {
    const retyped: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const [path, before] of Object.entries(step.keys)) {
        const after = now.keys[path];
        if (!after || after.type === before.type) continue;
        if (isDeclared(path)) continue;
        retyped.push(`${step.label} ${path}: ${before.type} -> ${after.type}`);
      }
    }
    expect(retyped, "an undeclared type change breaks a consumer's parse").toEqual([]);
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

  test("no scalar value changed, unless declared", () => {
    const changed: string[] = [];
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      for (const [path, before] of Object.entries(step.keys)) {
        const after = now.keys[path];
        if (!after || after.type !== before.type) continue;
        // object/array shape is covered by the test above.
        if (before.type === "object" || before.type === "array") continue;
        if (JSON.stringify(after.value) === JSON.stringify(before.value)) continue;
        if (isDeclared(path)) continue;
        changed.push(
          `${step.label} ${path}: ${JSON.stringify(before.value)} -> ${JSON.stringify(after.value)}`
        );
      }
    }
    expect(changed, "an undeclared behaviour change is a silent contract break").toEqual([]);
  });

  // The release IS additive: prove it added something, so a future refactor that
  // quietly drops every new field cannot pass by doing nothing.
  test("the release is additive: new keys were introduced", () => {
    let added = 0;
    for (const step of golden.steps) {
      const now = stepOf(current, step.label);
      if (!now) continue;
      added += Object.keys(now.keys).filter((path) => !(path in step.keys)).length;
    }
    expect(added).toBeGreaterThan(0);
  });
});

// The golden is not just a contract — it is a RECORDING of the 0.4.0 bug. Pin
// that, so the fix can never silently regress: 0.4.0 shows a row losing its
// evidence when an unrelated row is verified; the current build must not.
describe("the 0.4.0 golden records the data-loss bug the release fixes", () => {
  test("0.4.0 lost a row's evidence after `verify --row`; the current build does not", () => {
    const before = stepOf(golden, "scan.after_single_row");
    const after = stepOf(current, "scan.after_single_row");
    expect(before).toBeDefined();
    expect(after).toBeDefined();

    // Find a row that 0.4.0 demoted to UNVERIFIED_LOCAL even though the single-row
    // verify never touched it.
    const victims = Object.entries(before!.keys).filter(
      ([path, entry]) =>
        /^\$\.data\.status\.rows\[\d+\]\.local_status$/.test(path) &&
        entry.value === "UNVERIFIED_LOCAL"
    );
    expect(victims.length, "the 0.4.0 golden should record at least one wiped row").toBeGreaterThan(0);

    // Every one of them must now survive with its evidence intact.
    for (const [path] of victims) {
      expect(after!.keys[path]?.value, `${path} must keep its evidence`).toBe("VERIFIED_LOCAL");
    }
  });
});
