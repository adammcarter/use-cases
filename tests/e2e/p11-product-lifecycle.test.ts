import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../packages/ucm-mcp/src/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const zeroHash = "sha256:0000000000000000000000000000000000000000000000000000000000000000";

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
});

describe("P11 product lifecycle examples", () => {
  test("runs the complete product lifecycle on the clean example", () => {
    const workspaceRoot = exampleWorkspace("basic-product");
    expect(readFileSync(join(workspaceRoot, "evidence/by-id/ev/evidence-basic-search.jsonl"), "utf8")).not.toContain(zeroHash);
    expect(readFileSync(join(workspaceRoot, "showcase-runs/run.basic.product.search/events.jsonl"), "utf8")).not.toContain(zeroHash);

    const validate = runCliJson(["matrix", "validate", "--repo", workspaceRoot, "--json"]);
    expect(validate.status).toBe(0);
    expect(validate.payload).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: true,
      data: {
        complete: true,
        counts: {
          use_cases_addressable: 2
        }
      }
    });

    const existingRun = runCliJson(["showcase", "status", "--repo", workspaceRoot, "--run", "run.basic.product.search", "--json"]);
    expect(existingRun.status).toBe(0);
    expect(existingRun.payload).toMatchObject({
      command: "showcase.status",
      data: {
        execution_status: "completed",
        run_outcome: "passed",
        approval_state: "pending"
      }
    });

    const evidence = runCliJson([
      "evidence",
      "record",
      "--repo",
      workspaceRoot,
      "--use-case",
      "product.search.golden",
      "--kind",
      "test_result",
      "--result",
      "pass",
      "--summary",
      "End-to-end test recorded the search golden path.",
      "--idempotency-key",
      "p11:evidence:product.search.golden",
      "--json"
    ]);
    expect(evidence.status).toBe(0);
    expect(evidence.payload.data.event.payload).toMatchObject({
      kind: "test_result",
      result: "pass",
      use_case_ids: ["product.search.golden"]
    });

    const plan = runCliJson([
      "plan",
      "showcase",
      "--repo",
      workspaceRoot,
      "--max-items",
      "1",
      "--host",
      "codex.cli",
      "--json"
    ]);
    expect(plan.status).toBe(0);
    expect(plan.payload.data.plan.selected_items[0]).toMatchObject({
      use_case_id: "product.search.golden"
    });
    const generatedPlan = plan.payload.data.plan;
    const planPath = join(workspaceRoot, "presentation-plans", "p11-generated-showcase.json");
    mkdirSync(join(workspaceRoot, "presentation-plans"), { recursive: true });
    writeFileSync(planPath, `${JSON.stringify(generatedPlan, null, 2)}\n`);

    const start = runCliJson([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--plan-file",
      planPath,
      "--idempotency-key",
      "p11:showcase:start",
      "--json"
    ]);
    expect(start.status).toBe(0);
    const runId = start.payload.data.run_id as string;
    const planItemId = start.payload.data.status.items[0].plan_item_id as string;
    expect(start.payload.data.event.payload.plan_content_hash).toBe(generatedPlan.plan_content_hash);

    expect(
      runCliJson([
        "showcase",
        "record-observation",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        planItemId,
        "--text",
        "The product search result appeared in the live demo.",
        "--json"
      ]).status
    ).toBe(0);
    expect(
      runCliJson([
        "showcase",
        "record-verdict",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        planItemId,
        "--verdict",
        "pass",
        "--actor",
        "user",
        "--json"
      ]).status
    ).toBe(0);
    expect(runCliJson(["showcase", "finish", "--repo", workspaceRoot, "--run", runId, "--json"]).status).toBe(0);
    expect(runCliJson(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]).payload.data).toMatchObject({
      execution_status: "completed",
      run_outcome: "passed",
      approval_state: "pending"
    });

    const status = runCliJson(["matrix", "status", "--repo", workspaceRoot, "--json"]);
    expect(status.status).toBe(0);
    expect(status.payload).toMatchObject({
      command: "matrix.status",
      ok: true,
      complete: true,
      data: {
        complete: true,
        evidence: {
          counts: {
            aggregates_active: expect.any(Number)
          }
        }
      }
    });
    expect(status.payload.data.evidence.counts.aggregates_active).toBeGreaterThanOrEqual(2);

    const mcp = callMcpTool("matrix_validate", { repo: workspaceRoot });
    expect(mcp).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: true,
      data: {
        counts: validate.payload.data.counts
      }
    });
  });

  test("reports damaged example input without bringing down the system", () => {
    const workspaceRoot = exampleWorkspace("damaged-product");

    const validate = runCliJson(["matrix", "validate", "--repo", workspaceRoot, "--json"]);
    expect(validate.status).toBe(1);
    expect(validate.payload).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: false,
      data: {
        complete: false,
        integrity: {
          state: "partial"
        },
        counts: {
          use_cases_addressable: 1,
          use_cases_ambiguous: 2
        }
      }
    });
    expect(validate.payload.diagnostics).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ code: "parse_error" }),
        expect.objectContaining({ code: "duplicate_id" })
      ])
    );

    const evidence = runCliJson(["evidence", "status", "--repo", workspaceRoot, "--json"]);
    expect(evidence.status).toBe(1);
    expect(evidence.payload).toMatchObject({
      command: "evidence.status",
      ok: false,
      complete: false,
      data: {
        integrity: {
          state: "unusable"
        }
      }
    });
    expect(evidence.payload.diagnostics).toEqual(
      expect.arrayContaining([expect.objectContaining({ code: "evidence_parse_error" })])
    );
  });
});

describe("P11 host and project acceptance", () => {
  test("runs all host projection conformance without calling missing executables support", () => {
    const workspaceRoot = exampleWorkspace("host-projections");
    for (const host of ["claude", "codex", "copilot", "opencode"]) {
      expect(runCliJson(["host", "project", "--host", host, "--repo", workspaceRoot, "--write", "--json"]).status).toBe(0);
    }

    const conformance = runCliJson(["host", "conformance", "--all", "--repo", workspaceRoot, "--json"]);
    expect(conformance.status).toBe(0);
    expect(conformance.payload).toMatchObject({
      command: "host.conformance",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        hosts: expect.arrayContaining([
          expect.objectContaining({ host: "claude" }),
          expect.objectContaining({ host: "codex" }),
          expect.objectContaining({ host: "copilot" }),
          expect.objectContaining({ host: "opencode" })
        ])
      }
    });
    for (const host of conformance.payload.data.hosts as Array<Record<string, unknown>>) {
      expect(host.evidence_event_ids).toEqual([]);
      expect(host.support_status).not.toBe("verified_with_evidence");
      expect(host.executable_smoke).toEqual(
        expect.objectContaining({
          status: expect.stringMatching(/^(passed|failed|not_run)$/),
          reason: expect.any(String)
        })
      );
      if ((host.executable_smoke as { status: string }).status === "not_run") {
        expect((host.executable_smoke as { reason: string }).reason).toMatch(/not found|unavailable/i);
      }
    }
  });

  test("dogfoods the project acceptance matrix and documents acceptance", () => {
    expect(existsSync(join(repoRoot, "docs", "acceptance.md"))).toBe(true);

    const validate = runCliJson(["matrix", "validate", "--repo", repoRoot, "--json"]);
    expect(validate.status).toBe(0);
    expect(validate.payload).toMatchObject({
      command: "matrix.validate",
      ok: true,
      complete: true,
      data: {
        counts: {
          use_cases_addressable: 8
        }
      }
    });

    const listed = runCliJson(["matrix", "list", "--repo", repoRoot, "--json"]);
    expect(listed.status).toBe(0);
    expect((listed.payload.data.use_cases as Array<{ id: string }>).map((item) => item.id)).toEqual([
      "evidence.core.record",
      "hosts.projections.all",
      "matrix.core.validate",
      "mcp.use_case_mutation.safe",
      "mcp.wrapper.parity",
      "migration.test_matrix.draft",
      "release.package.installable_artifact",
      "showcase.live.user_signoff"
    ]);
  });
});

function exampleWorkspace(name: string): string {
  const sourceRoot = join(repoRoot, "examples", name);
  expect(existsSync(sourceRoot)).toBe(true);
  const workspaceRoot = mkdtempSync(join(tmpdir(), `presentation-skills-p11-${name}-`));
  cpSync(sourceRoot, workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function callMcpTool(name: string, args: Record<string, unknown>) {
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

function runCliJson(args: string[]) {
  const result = run("node", ["packages/ucm-cli/dist/index.js", ...args]);
  return {
    ...result,
    payload: parseJsonOutput(result)
  };
}

function run(command: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [
        `command failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}

function parseJsonOutput(result: SpawnSyncReturns<string>): Record<string, any> {
  try {
    return JSON.parse(result.stdout) as Record<string, any>;
  } catch (error) {
    throw new Error(
      [
        `failed to parse CLI JSON: ${error instanceof Error ? error.message : String(error)}`,
        `status: ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}
