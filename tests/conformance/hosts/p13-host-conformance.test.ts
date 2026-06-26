import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

beforeAll(() => {
  const build = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (build.status !== 0) {
    throw new Error(build.stderr || build.stdout);
  }
}, 30_000);

describe("P13 host conformance status semantics", () => {
  test("reports a missing host executable as warning-backed not_run without failing the command", () => {
    const workspaceRoot = projectedWorkspace();
    const emptyPath = mkdtempSync(join(tmpdir(), "presentation-skills-empty-path-"));

    const result = runCli(["host", "conformance", "--host", "codex", "--repo", workspaceRoot, "--json"], {
      PATH: emptyPath
    });
    const payload = JSON.parse(result.stdout);

    expect(result.status).toBe(0);
    expect(payload).toMatchObject({
      command: "host.conformance",
      ok: true,
      complete: true,
      diagnostics: [
        expect.objectContaining({
          code: "host.executable_not_found",
          severity: "warning"
        })
      ],
      data: {
        support_status: "conformant_static",
        evidence_event_ids: [],
        executable_smoke: {
          status: "not_run",
          executable: "codex",
          reason_code: "executable_not_found",
          exit_code: null
        }
      }
    });
    expect(payload.data.support_status).not.toBe("verified_with_evidence");
  });

  test("keeps static conformance green when the host executable smoke passes", () => {
    const workspaceRoot = projectedWorkspace();
    const binPath = pathWithExecutable("codex", "echo codex 1.2.3\nexit 0");

    const result = runCli(["host", "conformance", "--host", "codex", "--repo", workspaceRoot, "--json"], {
      PATH: binPath
    });
    const payload = JSON.parse(result.stdout);

    expect(result.status).toBe(0);
    expect(payload).toMatchObject({
      command: "host.conformance",
      ok: true,
      complete: true,
      diagnostics: [],
      data: {
        support_status: "conformant_static",
        executable_smoke: {
          status: "passed",
          executable: "codex",
          reason_code: "ok",
          exit_code: 0
        }
      }
    });
  });

  test("reports unavailable subcommands as warning-backed not_run", () => {
    const workspaceRoot = projectedWorkspace();
    const binPath = pathWithExecutable("codex", "echo command not installed >&2\nexit 2");

    const result = runCli(["host", "conformance", "--host", "codex", "--repo", workspaceRoot, "--json"], {
      PATH: binPath
    });
    const payload = JSON.parse(result.stdout);

    expect(result.status).toBe(0);
    expect(payload).toMatchObject({
      command: "host.conformance",
      ok: true,
      complete: true,
      diagnostics: [
        expect.objectContaining({
          code: "host.executable_unavailable",
          severity: "warning"
        })
      ],
      data: {
        support_status: "conformant_static",
        executable_smoke: {
          status: "not_run",
          executable: "codex",
          reason_code: "executable_unavailable",
          exit_code: 2
        }
      }
    });
  });

  test("fails the command when a resolved host executable smoke exits unsuccessfully", () => {
    const workspaceRoot = projectedWorkspace();
    const binPath = pathWithExecutable("codex", "echo smoke failed >&2\nexit 17");

    const result = runCli(["host", "conformance", "--host", "codex", "--repo", workspaceRoot, "--json"], {
      PATH: binPath
    });
    const payload = JSON.parse(result.stdout);

    expect(result.status).toBe(1);
    expect(payload).toMatchObject({
      command: "host.conformance",
      ok: false,
      complete: false,
      diagnostics: [
        expect.objectContaining({
          code: "host.executable_smoke_failed",
          severity: "error"
        })
      ],
      data: {
        support_status: "blocked",
        evidence_event_ids: [],
        executable_smoke: {
          status: "failed",
          executable: "codex",
          reason_code: "nonzero_exit",
          exit_code: 17,
          stderr: "smoke failed"
        }
      }
    });
    expect(payload.data.support_status).not.toBe("verified_with_evidence");
  });

  test("fails --all when any resolved host executable smoke fails", () => {
    const workspaceRoot = projectedWorkspace();
    const binPath = pathWithExecutable("codex", "echo smoke failed >&2\nexit 17");

    const result = runCli(["host", "conformance", "--all", "--repo", workspaceRoot, "--json"], {
      PATH: binPath
    });
    const payload = JSON.parse(result.stdout);

    expect(result.status).toBe(1);
    expect(payload).toMatchObject({
      command: "host.conformance",
      ok: false,
      complete: false,
      diagnostics: expect.arrayContaining([
        expect.objectContaining({
          code: "host.executable_smoke_failed",
          severity: "error"
        })
      ]),
      data: {
        complete: false,
        summary: {
          total_hosts: 4,
          executable_smoke_failed: 1,
          executable_smoke_not_run: 3
        },
        hosts: expect.arrayContaining([
          expect.objectContaining({
            host: "codex",
            support_status: "blocked",
            executable_smoke: expect.objectContaining({ status: "failed" })
          })
        ])
      }
    });
  });
});

function projectedWorkspace(): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "presentation-skills-host-conformance-"));
  cpSync(join(repoRoot, "examples", "host-projections"), workspaceRoot, { recursive: true, errorOnExist: false });
  rmSync(join(workspaceRoot, ".codex"), { recursive: true, force: true });
  rmSync(join(workspaceRoot, ".presentation-skills-projection.json"), { force: true });

  const project = runCli(["host", "project", "--host", "codex", "--repo", workspaceRoot, "--write", "--json"]);
  if (project.status !== 0) {
    throw new Error(project.stderr || project.stdout);
  }
  return workspaceRoot;
}

function pathWithExecutable(name: string, body: string): string {
  const binPath = mkdtempSync(join(tmpdir(), "presentation-skills-host-bin-"));
  const executablePath = join(binPath, name);
  writeFileSync(executablePath, `#!/bin/sh\n${body}\n`);
  chmodSync(executablePath, 0o755);
  return binPath;
}

function runCli(args: string[], env: Record<string, string> = {}) {
  return spawnSync(process.execPath, ["packages/ucm-cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...env }
  });
}
