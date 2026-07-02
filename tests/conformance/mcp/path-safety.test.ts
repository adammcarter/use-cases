import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../../packages/mcp/src/index.js";

// SECURITY (path traversal): the MCP `run`/`item` ids share the CLI's filesystem
// path/lookup sinks. They must be rejected with the stable UCM_INVALID_ID envelope
// and never read/write outside the workspace.

const repoRoot = resolve(import.meta.dirname, "../../..");

function callTool(name: string, args: Record<string, unknown>) {
  const response = handleMcpMessage({
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: { name, arguments: args }
  });
  if (!response?.result) {
    throw new Error(JSON.stringify(response));
  }
  return (response.result as { structuredContent: unknown }).structuredContent;
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-mcp-pathsafety-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function withMcpWriteMode<T>(fn: () => T): T {
  const previous = process.env.UCM_MCP_WRITE;
  process.env.UCM_MCP_WRITE = "1";
  try {
    return fn();
  } finally {
    if (previous === undefined) {
      delete process.env.UCM_MCP_WRITE;
    } else {
      process.env.UCM_MCP_WRITE = previous;
    }
  }
}

const MALICIOUS_RUN_IDS = ["../../../etc/passwd", "/etc/passwd", "run/../../escape", "..", "run/sub"];

describe("P-sec MCP rejects unsafe run/item ids", () => {
  beforeAll(() => {
    const built = spawnSync("corepack", ["pnpm", "build"], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    });
    if (built.status !== 0) {
      throw new Error(built.stderr || built.stdout);
    }
  });

  test.each(MALICIOUS_RUN_IDS)("showcase_status rejects run '%s' with UCM_INVALID_ID", (runId) => {
    const fixture = fixtureWorkspace("evidence-basic");
    const envelope = callTool("showcase_status", { repo: fixture, run: runId });
    expect(envelope).toMatchObject({
      command: "showcase.status",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
    });
  });

  test("showcase_record_observation with a traversal run writes NO file outside the workspace", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const escapeMarker = join(fixture, "..", "pwned-mcp");
    const envelope = withMcpWriteMode(() =>
      callTool("showcase_record_observation", {
        repo: fixture,
        allow_write: true,
        run: "../pwned-mcp",
        item: "item.showcase.live.golden",
        text: "exploit attempt"
      })
    );
    expect(envelope).toMatchObject({
      command: "showcase.record-observation",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
    });
    expect(existsSync(escapeMarker)).toBe(false);
  });

  test("showcase_record_observation rejects a traversal item with UCM_INVALID_ID", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const envelope = withMcpWriteMode(() =>
      callTool("showcase_record_observation", {
        repo: fixture,
        allow_write: true,
        run: "run.safe",
        item: "../../escape",
        text: "exploit attempt"
      })
    );
    expect(envelope).toMatchObject({
      command: "showcase.record-observation",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_INVALID_ID" })]
    });
  });
});

// SECURITY (path traversal): the MCP showcase_start `plan_file` arg shares the CLI's
// resolve(workspace_root, path) + readFileSync sink. A traversal value, an absolute path
// outside the workspace, or an in-workspace symlink to an outside file must be rejected
// with the stable UCM_PATH_ESCAPE envelope and read NOTHING outside the workspace.
describe("P-sec MCP bounds plan_file to the workspace", () => {
  beforeAll(() => {
    const built = spawnSync("corepack", ["pnpm", "build"], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    });
    if (built.status !== 0) {
      throw new Error(built.stderr || built.stdout);
    }
  });

  function generatePlan(fixture: string): unknown {
    const envelope = callTool("plan_showcase", {
      repo: fixture,
      max_items: 1,
      host: "codex.cli",
      generated_at: "2026-06-25T12:00:00.000Z"
    }) as { data: { plan: unknown } };
    return envelope.data.plan;
  }

  test("showcase_start rejects a traversal plan_file with UCM_PATH_ESCAPE", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const envelope = withMcpWriteMode(() =>
      callTool("showcase_start", { repo: fixture, allow_write: true, plan_file: "../../etc/passwd" })
    );
    expect(envelope).toMatchObject({
      command: "showcase.start",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_PATH_ESCAPE" })]
    });
  });

  test("showcase_start rejects an absolute plan_file outside the workspace even when it is a valid plan", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const plan = generatePlan(fixture);
    const outsideDir = mkdtempSync(join(tmpdir(), "use-case-matrix-mcp-pathsafety-outside-"));
    const outsidePlan = join(outsideDir, "plan.json");
    writeFileSync(outsidePlan, `${JSON.stringify(plan, null, 2)}\n`);
    const envelope = withMcpWriteMode(() =>
      callTool("showcase_start", { repo: fixture, allow_write: true, plan_file: outsidePlan })
    );
    expect(envelope).toMatchObject({
      command: "showcase.start",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_PATH_ESCAPE" })]
    });
  });

  test("showcase_start rejects a plan_file symlink that points outside the workspace", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const plan = generatePlan(fixture);
    const outsideDir = mkdtempSync(join(tmpdir(), "use-case-matrix-mcp-pathsafety-outside-"));
    const outsidePlan = join(outsideDir, "plan.json");
    writeFileSync(outsidePlan, `${JSON.stringify(plan, null, 2)}\n`);
    mkdirSync(join(fixture, "presentation-plans"), { recursive: true });
    symlinkSync(outsidePlan, join(fixture, "presentation-plans", "link.json"));
    const envelope = withMcpWriteMode(() =>
      callTool("showcase_start", { repo: fixture, allow_write: true, plan_file: "presentation-plans/link.json" })
    );
    expect(envelope).toMatchObject({
      command: "showcase.start",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "UCM_PATH_ESCAPE" })]
    });
  });
});
