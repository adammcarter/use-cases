import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../../packages/mcp/src/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

describe("P9 MCP wrapper contract", () => {
  test("lists conservative v1 tools and omits deferred write/approval tools", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
    const names = ((response?.result as { tools: Array<{ name: string }> }).tools).map((tool) => tool.name);

    expect(names).toContain("matrix_validate");
    expect(names).toContain("evidence_record");
    expect(names).toContain("showcase_request_approval");
    expect(names).toContain("host_doctor");
    expect(names).not.toContain("ucm_upsert_use_case");
    expect(names).not.toContain("showcase_approve");
    expect(names).not.toContain("host_project");
  });

  test("matrix_validate returns the same envelope as CLI matrix validate", () => {
    build();
    const fixture = resolve(repoRoot, "tests/fixtures/workspaces/minimal-valid");
    const cli = runCli(["matrix", "validate", "--repo", fixture, "--json"]);
    const mcp = callTool("matrix_validate", { repo: fixture });

    expect(mcp).toEqual(cli);
  });

  test("workspace tools require an explicit repository root", () => {
    const envelope = callTool("matrix_validate", {});

    expect(envelope).toMatchObject({
      command: "matrix.validate",
      ok: false,
      complete: false,
      diagnostics: [expect.objectContaining({ code: "mcp.repo_required" })]
    });
  });

  // Regression (dogfood finding N1): a non-existent --repo/repo is a typo, not a
  // valid empty workspace. Both transports must reject it IDENTICALLY — otherwise
  // the matrix inspection tools silently report a missing path as valid:true with
  // zero use cases, and the "same JSON contract on both transports" guarantee
  // breaks. The guard lives in the shared core resolver (workspaceNotFoundDiagnostic)
  // so every matrix tool (and any future one) inherits it, and the CLI + MCP emit a
  // byte-identical envelope.
  test("matrix inspection tools reject a non-existent repo identically on CLI and MCP (workspace.not_found parity)", () => {
    build();
    const missing = resolve(repoRoot, "tests/fixtures/workspaces/__ucm_definitely_missing_repo__");
    const tools: Array<[string, string[]]> = [
      ["matrix_validate", ["matrix", "validate"]],
      ["matrix_list", ["matrix", "list"]],
      ["matrix_status", ["matrix", "status"]]
    ];
    for (const [tool, cliArgs] of tools) {
      const mcp = callTool(tool, { repo: missing });
      expect(mcp, tool).toMatchObject({
        ok: false,
        complete: false,
        diagnostics: [expect.objectContaining({ code: "workspace.not_found" })]
      });

      const cli = runCliRaw([...cliArgs, "--repo", missing, "--json"]);
      expect(cli.exitCode, `${tool}: CLI must exit 2 on a non-existent repo`).toBe(2);
      expect(cli.envelope, `${tool}: CLI and MCP envelopes must match`).toEqual(mcp);
    }
  });

  test("write tools require explicit write mode before mutating ledgers", () => {
    const fixture = fixtureWorkspace("evidence-basic");
    const before = readTreeBytes(join(fixture, "evidence"));
    const envelope = callTool("evidence_record", {
      repo: fixture,
      use_case: "showcase.live.golden",
      kind: "manual_observation",
      result: "observed",
      summary: "Observed through MCP."
    });

    expect(envelope).toMatchObject({
      command: "evidence.record",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.write_mode_required" })]
    });
    expect(readTreeBytes(join(fixture, "evidence"))).toEqual(before);
  });

  test("showcase_record_verdict cannot claim a trusted user actor", () => {
    const { fixture, runId, planItemId, ledgerPath } = completedShowcaseRun();
    const before = readFileSync(ledgerPath, "utf8");
    const envelope = withMcpWriteMode(() => callTool("showcase_record_verdict", {
      repo: fixture,
      allow_write: true,
      run: runId,
      item: planItemId,
      verdict: "pass",
      actor_type: "user"
    }));

    expect(envelope).toMatchObject({
      command: "showcase.record-verdict",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.trusted_confirmation_required" })]
    });
    expect(readFileSync(ledgerPath, "utf8")).toEqual(before);
  });

  test("showcase_request_approval prepares a CLI-mediated approval request without appending approval", () => {
    const { fixture, runId, ledgerPath } = completedShowcaseRun();
    const before = readFileSync(ledgerPath, "utf8");
    const envelope = callTool("showcase_request_approval", {
      repo: fixture,
      run: runId,
      statement: "Approved after observing the run."
    });

    expect(envelope).toMatchObject({
      command: "showcase.request-approval",
      ok: true,
      data: {
        decision_required: true,
        trusted_confirmation_required: true,
        run_id: runId,
        suggested_cli_command: expect.arrayContaining(["showcase", "approve", "--run", runId])
      }
    });
    expect(readFileSync(ledgerPath, "utf8")).toEqual(before);
  });

  test("timeout gate returns a structured error before partial showcase writes", () => {
    const { fixture, runId, planItemId, ledgerPath } = completedShowcaseRun();
    const before = readFileSync(ledgerPath, "utf8");
    const envelope = callTool("showcase_record_observation", {
      repo: fixture,
      allow_write: true,
      timeout_ms: 0,
      run: runId,
      item: planItemId,
      text: "This should not be written."
    });

    expect(envelope).toMatchObject({
      command: "showcase.record-observation",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.timeout" })]
    });
    expect(readFileSync(ledgerPath, "utf8")).toEqual(before);
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

function build() {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
}

function runCli(args: string[]) {
  const result = spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8"
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
  return JSON.parse(result.stdout);
}

// Like runCli, but for the failure paths: capture the exit code and parsed
// envelope WITHOUT throwing on a non-zero exit (workspace.not_found exits 2).
function runCliRaw(args: string[]): { exitCode: number | null; envelope: unknown } {
  const result = spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8"
  });
  return { exitCode: result.status, envelope: JSON.parse(result.stdout) };
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-case-matrix-mcp-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function completedShowcaseRun() {
  build();
  const fixture = fixtureWorkspace("evidence-basic");
  const start = runCli([
    "showcase",
    "start",
    "--repo",
    fixture,
    "--adhoc",
    "--select",
    "showcase.live.golden",
    "--idempotency-key",
    "p9:start",
    "--json"
  ]);
  const runId = start.data.run_id as string;
  const planItemId = start.data.status.items[0].plan_item_id as string;
  runCli(["showcase", "record-observation", "--repo", fixture, "--run", runId, "--item", planItemId, "--text", "Observed.", "--json"]);
  runCli(["showcase", "record-verdict", "--repo", fixture, "--run", runId, "--item", planItemId, "--verdict", "pass", "--json"]);
  runCli(["showcase", "finish", "--repo", fixture, "--run", runId, "--json"]);
  return {
    fixture,
    runId,
    planItemId,
    ledgerPath: join(fixture, "showcase-runs", runId, "events.jsonl")
  };
}

function readTreeBytes(root: string): string {
  if (!existsSync(root)) {
    return "";
  }
  const parts: string[] = [];
  for (const entry of readdirSync(root).sort()) {
    const path = join(root, entry);
    if (statSync(path).isDirectory()) {
      parts.push(`${entry}/`, readTreeBytes(path));
    } else {
      parts.push(entry, readFileSync(path, "utf8"));
    }
  }
  return parts.join("\n");
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
