import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

// SECURITY (path traversal): user-supplied showcase --run / --item ids flow into
// data_root/showcase-runs/<id>/events.jsonl and into ledger lookups. A traversal
// id (../../../etc/passwd), an absolute id, or one containing '/'/'\\'/'..' must be
// rejected with the stable UCP_INVALID_ID envelope (exit 2) and must NOT cause any
// filesystem read/write outside the workspace.

const repoRoot = resolve(import.meta.dirname, "../../..");

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]) {
  return run("node", ["packages/ucm-cli/dist/index.js", ...args]);
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `presentation-skills-pathsafety-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

// Traversal ids that, unguarded, would escape data_root/showcase-runs/<id>.
const MALICIOUS_RUN_IDS = [
  "../../../etc/passwd",
  "/etc/passwd",
  "run/../../escape",
  "..",
  "run/sub"
];

describe("P-sec showcase CLI rejects unsafe run/item ids", () => {
  beforeAll(() => {
    const built = run("corepack", ["pnpm", "build"]);
    if (built.status !== 0) {
      throw new Error(built.stderr || built.stdout);
    }
  });

  test.each(MALICIOUS_RUN_IDS)(
    "showcase status rejects --run '%s' with UCP_INVALID_ID and exit 2",
    (runId) => {
      const workspaceRoot = fixtureWorkspace("evidence-basic");
      const result = runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]);
      expect(result.status).toBe(2);
      expect(JSON.parse(result.stdout)).toMatchObject({
        command: "showcase.status",
        ok: false,
        diagnostics: [expect.objectContaining({ code: "UCP_INVALID_ID" })]
      });
    }
  );

  test("showcase record-observation with a traversal --run writes NO file outside the workspace", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    // Resolves, if unguarded, to a sibling of the workspace named 'pwned'.
    const escapeMarker = join(workspaceRoot, "..", "pwned");
    const result = runCli([
      "showcase",
      "record-observation",
      "--repo",
      workspaceRoot,
      "--run",
      "../pwned",
      "--item",
      "item.showcase.live.golden",
      "--text",
      "exploit attempt",
      "--json"
    ]);
    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "showcase.record-observation",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_INVALID_ID" })]
    });
    expect(existsSync(escapeMarker)).toBe(false);
  });

  test("showcase record-observation rejects a traversal --item with UCP_INVALID_ID", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const start = runCli([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--adhoc",
      "--select",
      "showcase.live.golden",
      "--json"
    ]);
    expect(start.status).toBe(0);
    const runId = JSON.parse(start.stdout).data.run_id as string;
    const result = runCli([
      "showcase",
      "record-observation",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--item",
      "../../escape",
      "--text",
      "exploit attempt",
      "--json"
    ]);
    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "showcase.record-observation",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_INVALID_ID" })]
    });
  });

  test("a valid run id still works end to end (start -> status)", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const start = runCli([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--adhoc",
      "--select",
      "showcase.live.golden",
      "--json"
    ]);
    expect(start.status).toBe(0);
    const runId = JSON.parse(start.stdout).data.run_id as string;
    expect(isValidLike(runId)).toBe(true);

    const status = runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]);
    expect(status.status).toBe(0);
    expect(JSON.parse(status.stdout)).toMatchObject({
      command: "showcase.status",
      ok: true,
      data: { run_id: runId }
    });
  });
});

function isValidLike(value: string): boolean {
  return /^[a-z0-9][a-z0-9_-]*(?:\.[a-z0-9][a-z0-9_-]*)*$/.test(value);
}

// SECURITY (path traversal): user-supplied --plan-file flows into resolve(workspace_root,
// path) and is then read from disk. A traversal value ('../../etc/passwd'), an absolute
// path outside the workspace, or an in-workspace symlink that points outside must be
// rejected with the stable UCP_PATH_ESCAPE envelope (exit 4) and must read NOTHING
// outside the workspace. A legitimate in-workspace plan file must still work.
describe("P-sec CLI bounds --plan-file to the workspace", () => {
  beforeAll(() => {
    const built = run("corepack", ["pnpm", "build"]);
    if (built.status !== 0) {
      throw new Error(built.stderr || built.stdout);
    }
  });

  function generatePlan(workspaceRoot: string): unknown {
    const planResult = runCli([
      "plan",
      "showcase",
      "--repo",
      workspaceRoot,
      "--max-items",
      "1",
      "--host",
      "codex.cli",
      "--generated-at",
      "2026-06-25T12:00:00.000Z",
      "--json"
    ]);
    expect(planResult.status).toBe(0);
    return JSON.parse(planResult.stdout).data.plan;
  }

  function outsidePlanFile(plan: unknown): string {
    const outsideDir = mkdtempSync(join(tmpdir(), "presentation-skills-pathsafety-outside-"));
    const outsidePlan = join(outsideDir, "plan.json");
    writeFileSync(outsidePlan, `${JSON.stringify(plan, null, 2)}\n`);
    return outsidePlan;
  }

  test("plan cards rejects a traversal --plan-file with UCP_PATH_ESCAPE (exit 4)", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const result = runCli(["plan", "cards", "--repo", workspaceRoot, "--plan-file", "../../etc/passwd", "--json"]);
    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "plan.cards",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_PATH_ESCAPE" })]
    });
  });

  test("plan cards rejects an absolute --plan-file outside the workspace even when it is a valid plan", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    // A perfectly valid plan placed OUTSIDE the workspace must still be refused,
    // proving containment is enforced before the file is ever read.
    const outsidePlan = outsidePlanFile(generatePlan(workspaceRoot));
    const result = runCli(["plan", "cards", "--repo", workspaceRoot, "--plan-file", outsidePlan, "--json"]);
    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "plan.cards",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_PATH_ESCAPE" })]
    });
  });

  test("plan cards rejects a --plan-file symlink that points outside the workspace", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const outsidePlan = outsidePlanFile(generatePlan(workspaceRoot));
    mkdirSync(join(workspaceRoot, "presentation-plans"), { recursive: true });
    // Lexically in-workspace, but realpath tunnels outside via the symlink.
    symlinkSync(outsidePlan, join(workspaceRoot, "presentation-plans", "link.json"));
    const result = runCli([
      "plan",
      "cards",
      "--repo",
      workspaceRoot,
      "--plan-file",
      "presentation-plans/link.json",
      "--json"
    ]);
    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "plan.cards",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_PATH_ESCAPE" })]
    });
  });

  test("showcase start rejects a traversal --plan-file with UCP_PATH_ESCAPE (exit 4)", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const result = runCli(["showcase", "start", "--repo", workspaceRoot, "--plan-file", "../escape.json", "--json"]);
    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "showcase.start",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCP_PATH_ESCAPE" })]
    });
  });

  test("a legitimate in-workspace --plan-file still works", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const plan = generatePlan(workspaceRoot);
    mkdirSync(join(workspaceRoot, "presentation-plans"), { recursive: true });
    writeFileSync(join(workspaceRoot, "presentation-plans", "plan.json"), `${JSON.stringify(plan, null, 2)}\n`);
    const result = runCli([
      "plan",
      "cards",
      "--repo",
      workspaceRoot,
      "--plan-file",
      "presentation-plans/plan.json",
      "--json"
    ]);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({ command: "plan.cards", ok: true });
  });
});
