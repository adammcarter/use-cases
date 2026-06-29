import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";
import { handleMcpMessage } from "../../../packages/ucm-mcp/src/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
}, 30_000);

describe("P14 MCP use-case mutation tools", () => {
  test("lists safe use-case mutation tools", () => {
    const response = handleMcpMessage({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} });
    const names = ((response?.result as { tools: Array<{ name: string }> }).tools).map((tool) => tool.name);

    expect(names).toContain("use_case_upsert");
    expect(names).toContain("use_case_remove");
    expect(names).not.toContain("use_case_physical_delete");
  });

  test("requires write mode before mutating a use-case file", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const before = readFileSync(join(workspaceRoot, "use-cases/auth-login.yml"), "utf8");
    const envelope = callTool("use_case_upsert", {
      repo: workspaceRoot,
      file: "use-cases/auth-login.yml",
      use_case: plannedUseCase("auth.login.mcp_write_gate")
    });

    expect(envelope).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.write_mode_required" })]
    });
    expect(readFileSync(join(workspaceRoot, "use-cases/auth-login.yml"), "utf8")).toEqual(before);
  });

  test("adds and removes a planned use case through MCP write tools", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const useCaseId = "auth.login.mcp_mutation";
    const created = withMcpWriteMode(() => callTool("use_case_upsert", {
      repo: workspaceRoot,
      allow_write: true,
      file: "use-cases/auth-login.yml",
      use_case: plannedUseCase(useCaseId)
    }));

    expect(created).toMatchObject({
      command: "matrix.upsert",
      ok: true,
      complete: true,
      data: {
        status: "created",
        use_case_id: useCaseId
      }
    });

    const removed = withMcpWriteMode(() => callTool("use_case_remove", {
      repo: workspaceRoot,
      allow_write: true,
      use_case: useCaseId,
      reason: "MCP mutation test cleanup."
    }));

    expect(removed).toMatchObject({
      command: "matrix.remove",
      ok: true,
      complete: true,
      data: {
        status: "removed",
        use_case_id: useCaseId
      }
    });
    expect(readFileSync(join(workspaceRoot, "use-cases/auth-login.yml"), "utf8")).toContain("MCP mutation test cleanup.");
  });

  test("rejects model-controlled user claims before mutation", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const envelope = withMcpWriteMode(() => callTool("use_case_upsert", {
      repo: workspaceRoot,
      allow_write: true,
      actor_type: "user",
      file: "use-cases/auth-login.yml",
      use_case: plannedUseCase("auth.login.user_claim")
    }));

    expect(envelope).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "mcp.trusted_confirmation_required" })]
    });
  });

  test("rejects path escapes through MCP mutation", () => {
    const workspaceRoot = fixtureWorkspace("minimal-valid");
    const envelope = withMcpWriteMode(() => callTool("use_case_upsert", {
      repo: workspaceRoot,
      allow_write: true,
      file: "../escape.yml",
      use_case: plannedUseCase("auth.login.escape")
    }));

    expect(envelope).toMatchObject({
      command: "matrix.upsert",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "matrix.mutation_path_escape" })]
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
  const workspaceRoot = mkdtempSync(join(tmpdir(), `presentation-skills-mcp-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function plannedUseCase(id: string): Record<string, unknown> {
  return {
    id,
    title: "MCP managed planned case",
    lifecycle: "planned",
    value_tier: "supporting",
    journey_role: "alternate",
    usage_frequency: "occasional",
    tags: ["mcp", "mutation"]
  };
}

function withMcpWriteMode<T>(fn: () => T): T {
  const previous = process.env.UCP_MCP_WRITE;
  process.env.UCP_MCP_WRITE = "1";
  try {
    return fn();
  } finally {
    if (previous === undefined) {
      delete process.env.UCP_MCP_WRITE;
    } else {
      process.env.UCP_MCP_WRITE = previous;
    }
  }
}
