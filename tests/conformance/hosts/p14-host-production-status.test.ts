import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");
const hostTargets = {
  claude: ".claude/use-cases-plugin.md",
  codex: ".codex/use-cases-plugin.md",
  copilot: ".github/copilot/use-cases-plugin.md",
  opencode: ".opencode/use-cases-plugin.md"
} as const;

beforeAll(() => {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
}, 60_000);

describe("P14 host projection production status", () => {
  test("projects, reports, and reverts all first-class hosts without overstating support", () => {
    const workspaceRoot = fixtureWorkspace();
    for (const host of Object.keys(hostTargets)) {
      const projected = runCliJson(["host", "project", "--host", host, "--repo", workspaceRoot, "--write", "--json"]);
      expect(projected.status).toBe(0);
      expect(projected.payload).toMatchObject({
        command: "host.project",
        ok: true,
        complete: true,
        data: {
          host,
          mode: "write"
        }
      });
    }
    expect(existsSync(join(workspaceRoot, ".use-cases-plugin-projection.json"))).toBe(true);
    for (const target of Object.values(hostTargets)) {
      expect(existsSync(join(workspaceRoot, target))).toBe(true);
    }

    const conformance = runCliJson(["host", "conformance", "--all", "--repo", workspaceRoot, "--json"]);
    expect(conformance.status).toBe(0);
    expect(conformance.payload).toMatchObject({
      command: "host.conformance",
      ok: true,
      complete: true,
      data: {
        summary: {
          total_hosts: 4,
          static_conformant: 4
        }
      }
    });

    const hosts = conformance.payload.data.hosts as Array<Record<string, unknown>>;
    for (const host of Object.keys(hostTargets)) {
      const row = hosts.find((candidate) => candidate.host === host);
      expect(row).toMatchObject({
        host,
        status_basis: "static_conformance_only",
        support_status: "conformant_static",
        evidence_event_ids: [],
        support: {
          profile_available: true,
          projected: true,
          static_conformant: true,
          verified_with_evidence: false,
          evidence_event_ids: []
        },
        executable_smoke: {
          status: expect.stringMatching(/^(passed|not_run)$/),
          reason: expect.any(String)
        }
      });
      expect((row?.support as { executable_smoke: string }).executable_smoke).toBe(
        (row?.executable_smoke as { status: string }).status
      );
      if ((row?.executable_smoke as { status: string }).status === "not_run") {
        expect((row?.executable_smoke as { reason: string }).reason).toMatch(/not found|unavailable/i);
      }
    }

    for (const host of Object.keys(hostTargets)) {
      const reverted = runCliJson(["host", "project", "--host", host, "--repo", workspaceRoot, "--revert", "--json"]);
      expect(reverted.status).toBe(0);
    }
    expect(existsSync(join(workspaceRoot, ".use-cases-plugin-projection.json"))).toBe(false);
    for (const target of Object.values(hostTargets)) {
      expect(existsSync(join(workspaceRoot, target))).toBe(false);
    }
  });
});

function fixtureWorkspace(): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "use-cases-plugin-hosts-p14-"));
  cpSync(join(repoRoot, "examples", "host-projections"), workspaceRoot, { recursive: true, errorOnExist: false });
  return workspaceRoot;
}

function runCliJson(args: string[]) {
  const result = spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  return {
    status: result.status,
    payload: result.stdout ? JSON.parse(result.stdout) : null,
    stderr: result.stderr
  };
}
