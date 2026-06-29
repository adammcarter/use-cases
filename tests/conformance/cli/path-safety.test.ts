import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

// SECURITY (path traversal): user-supplied showcase --run / --item ids flow into
// data_root/showcase-runs/<id>/events.jsonl and into ledger lookups. A traversal
// id (../../../etc/passwd), an absolute id, or one containing '/'/'\\'/'..' must be
// rejected with the stable UCM_INVALID_ID envelope (exit 2) and must NOT cause any
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
    "showcase status rejects --run '%s' with UCM_INVALID_ID and exit 2",
    (runId) => {
      const workspaceRoot = fixtureWorkspace("evidence-basic");
      const result = runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]);
      expect(result.status).toBe(2);
      expect(JSON.parse(result.stdout)).toMatchObject({
        command: "showcase.status",
        ok: false,
        diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
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
      diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
    });
    expect(existsSync(escapeMarker)).toBe(false);
  });

  test("showcase record-observation rejects a traversal --item with UCM_INVALID_ID", () => {
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
      diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
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
