import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");
let handleMcpMessage: (message: Record<string, unknown>) => Record<string, unknown> | null;

beforeAll(async () => {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  const moduleUrl = `${pathToFileURL(join(repoRoot, "packages/mcp/dist/index.js")).href}?cache=${Date.now()}`;
  ({ handleMcpMessage } = await import(/* @vite-ignore */ moduleUrl));
}, 30_000);

describe("P14 MCP demo capsule runner", () => {
  test("lists capsule_run as a write tool", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
    const names = ((response?.result as { tools: Array<{ name: string }> }).tools).map((tool) => tool.name);

    expect(names).toContain("capsule_run");
  });

  test("requires write mode before running a capsule", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const envelope = callTool("capsule_run", {
      repo: workspaceRoot,
      capsule: "capsule.showcase.golden"
    });

    expect(envelope).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.write_mode_required" })]
    });
  });

  test("requires server write mode even when caller passes allow_write", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const envelope = callTool("capsule_run", {
      repo: workspaceRoot,
      allow_write: true,
      capsule: "capsule.showcase.golden"
    });

    expect(envelope).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.server_write_mode_required" })]
    });
  });

  test("runs a persisted capsule without recording approval when server write mode is enabled", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const envelope = withMcpWriteMode(() => callTool("capsule_run", {
      repo: workspaceRoot,
      allow_write: true,
      capsule: "capsule.showcase.golden"
    }));

    expect(envelope).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: false,
      data: {
        outcome: "performed",
        pending_steps: [expect.objectContaining({ reason: "runtime_observation_required" })],
        status: {
          execution_status: "running",
          run_outcome: "incomplete",
          approval_state: "pending"
        }
      }
    });
  });

  test("requires server command-execution mode for command-backed capsules", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    mkdirSync(join(workspaceRoot, "demo-capsules"), { recursive: true });
    writeFileSync(join(workspaceRoot, "demo-capsules", "command.yml"), [
      "schema_version: 1",
      "capsule_id: capsule.command.mcp",
      "title: MCP command capsule",
      "mode: showcase",
      "description: Exercise MCP command execution policy.",
      "audience: reviewer",
      "timebox_seconds: 600",
      "items:",
      "  - use_case_id: showcase.live.golden",
      "    scenario_ids: [showcase.live.golden.cli]",
      "    runbook:",
      "      - kind: command",
      `        executable: ${JSON.stringify(process.execPath)}`,
      "        argv: [\"-e\", \"process.exit(0)\"]",
      "        working_directory: \".\"",
      "        expected_exit_codes: [0]",
      "permissions:",
      "  command_execution: true"
    ].join("\n"));

    const blocked = withMcpWriteMode(() => callTool("capsule_run", {
      repo: workspaceRoot,
      allow_write: true,
      capsule: "capsule.command.mcp",
      execute_commands: true
    }));
    expect(blocked).toMatchObject({
      command: "capsule.run",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.server_command_execution_mode_required" })]
    });

    const performed = withMcpCommandMode(() => callTool("capsule_run", {
      repo: workspaceRoot,
      allow_write: true,
      capsule: "capsule.command.mcp",
      execute_commands: true
    }));
    expect(performed).toMatchObject({
      command: "capsule.run",
      ok: true,
      complete: true,
      data: {
        status: {
          execution_status: "completed",
          run_outcome: "passed",
          approval_state: "pending"
        }
      }
    });
  });
});

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
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-mcp-capsule-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function withMcpWriteMode<T>(fn: () => T): T {
  return withEnv({ UCM_MCP_WRITE: "1" }, fn);
}

function withMcpCommandMode<T>(fn: () => T): T {
  return withEnv({
    UCM_MCP_WRITE: "1",
    UCM_MCP_COMMAND_EXECUTION: "1"
  }, fn);
}

function withEnv<T>(values: Record<string, string>, fn: () => T): T {
  const previous = new Map(Object.keys(values).map((key) => [key, process.env[key]]));
  for (const [key, value] of Object.entries(values)) {
    process.env[key] = value;
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}
