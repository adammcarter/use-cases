import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(async () => {
  await runPnpm(["build"]);
}, 30_000);

describe("P13 compiled MCP stdio parity", () => {
  test("runs the generated-plan showcase lifecycle over the compiled stdio server", async () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const client = await startMcpServer();
    try {
      const planEnvelope = await client.callTool("plan_showcase", {
        repo: workspaceRoot,
        max_items: 1,
        host: "codex.cli",
        generated_at: "2026-06-25T12:00:00.000Z"
      });
      const plan = (planEnvelope.data as { plan: Record<string, unknown> }).plan;
      const planPath = join(workspaceRoot, "presentation-plans", "mcp-generated-plan.json");
      mkdirSync(join(workspaceRoot, "presentation-plans"), { recursive: true });
      writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`);

      const startEnvelope = await client.callTool("showcase_start", {
        repo: workspaceRoot,
        allow_write: true,
        plan_file: planPath,
        idempotency_key: "p13:mcp:plan-file:start"
      });
      expect(startEnvelope).toMatchObject({
        command: "showcase.start",
        ok: true,
        data: {
          event: {
            payload: {
              plan_content_hash: plan.plan_content_hash
            }
          }
        }
      });
      const runId = (startEnvelope.data as { run_id: string }).run_id;
      const planItemId = ((startEnvelope.data as { status: { items: Array<{ plan_item_id: string }> } }).status.items[0]).plan_item_id;

      await expect(client.callTool("showcase_record_observation", {
        repo: workspaceRoot,
        allow_write: true,
        run: runId,
        item: planItemId,
        text: "Observed through compiled MCP stdio."
      })).resolves.toMatchObject({ command: "showcase.record-observation", ok: true });
      await expect(client.callTool("showcase_record_verdict", {
        repo: workspaceRoot,
        allow_write: true,
        run: runId,
        item: planItemId,
        verdict: "pass"
      })).resolves.toMatchObject({ command: "showcase.record-verdict", ok: true });
      await expect(client.callTool("showcase_finish", {
        repo: workspaceRoot,
        allow_write: true,
        run: runId
      })).resolves.toMatchObject({ command: "showcase.finish", ok: true });

      const statusEnvelope = await client.callTool("showcase_status", { repo: workspaceRoot, run: runId });
      expect(statusEnvelope).toMatchObject({
        command: "showcase.status",
        ok: true,
        data: {
          execution_status: "completed",
          run_outcome: "passed",
          approval_state: "pending"
        }
      });

      const ledgerPath = join(workspaceRoot, "showcase-runs", runId, "events.jsonl");
      const beforeApprovalRequest = readFileSync(ledgerPath, "utf8");
      await expect(client.callTool("showcase_request_approval", {
        repo: workspaceRoot,
        run: runId,
        statement: "User approval is still required."
      })).resolves.toMatchObject({
        command: "showcase.request-approval",
        ok: true,
        data: {
          decision_required: true,
          trusted_confirmation_required: true
        }
      });
      expect(readFileSync(ledgerPath, "utf8")).toEqual(beforeApprovalRequest);
    } finally {
      await client.close();
    }
  });
});

type McpEnvelope = {
  command: string;
  ok: boolean;
  data: unknown;
  diagnostics: unknown[];
};

async function startMcpServer() {
  const child = spawn(process.execPath, ["packages/mcp/dist/index.js", "--stdio"], {
    cwd: repoRoot,
    stdio: ["pipe", "pipe", "pipe"],
    env: {
      ...process.env,
      UCM_MCP_WRITE: "1"
    }
  });
  const lines: string[] = [];
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    lines.push(...chunk.split("\n").map((line) => line.trim()).filter(Boolean));
  });
  let nextId = 1;

  async function request(method: string, params: Record<string, unknown> = {}) {
    const id = nextId++;
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return waitForResponse(lines, id);
  }

  await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "p13-stdio-parity", version: "0.0.0" }
  });
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);

  return {
    async callTool(name: string, args: Record<string, unknown>): Promise<McpEnvelope> {
      const response = await request("tools/call", { name, arguments: args });
      return (response.result as { structuredContent: McpEnvelope }).structuredContent;
    },
    async close(): Promise<void> {
      child.stdin.end();
      await once(child, "exit");
    }
  };
}

async function waitForResponse(lines: string[], id: number): Promise<Record<string, unknown>> {
  const started = Date.now();
  while (Date.now() - started < 10_000) {
    for (const line of lines) {
      const response = JSON.parse(line) as { id?: number };
      if (response.id === id) {
        return response as Record<string, unknown>;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`timed out waiting for MCP response ${id}`);
}

async function runPnpm(args: string[]) {
  const child = spawn("corepack", ["pnpm", ...args], {
    cwd: repoRoot,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  const [code] = (await once(child, "exit")) as [number | null];
  if (code !== 0) {
    throw new Error(`corepack pnpm ${args.join(" ")} failed with ${code}`);
  }
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-mcp-stdio-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}
