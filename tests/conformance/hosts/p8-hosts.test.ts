import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../../packages/ucm-core/src/schema/index.js";
import { resolveWorkspaceContext } from "../../../packages/ucm-core/src/roots.js";
import {
  loadHostProfile,
  projectHostFiles,
  runHostConformance,
  runHostDoctor
} from "../../../packages/ucm-core/src/hosts/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

describe("P8 host profiles, projections, and conformance", () => {
  test("host profile schema rejects proof fields", () => {
    const badProfile = {
      schema_version: 1,
      profile_id: "codex.cli.default",
      host: "codex",
      surface: "codex.cli",
      profile_version: 1,
      host_version: { min: null, tested: null, notes: null },
      os_runtime: { supported: ["darwin"] },
      installation_mode: { expected: "repo_projection" },
      permission_mode: { expected: "workspace_write" },
      expected_capabilities: { skill_discovery: "required", cli_access: "required" },
      projection_targets: [{ kind: "activation_stub", path: ".codex/use-cases-plugin.md", managed: true }],
      doctor_checks: ["projection_manifest_optional", "cli_available"],
      conformance_checks: ["canonical_skill_hashes_match"],
      known_limitations: [],
      verified: true,
      status: "verified",
      last_verified_at: "2026-06-25T12:00:00.000Z",
      supporting_evidence_ids: []
    };

    expect(
      validateBySchemaId("https://use-cases-plugin.dev/schemas/v1/host-profile.schema.json", badProfile)
    ).toMatchObject({ ok: false });
  });

  test("canonical profiles load as expectation data for all four hosts", () => {
    for (const host of ["claude", "codex", "copilot", "opencode"] as const) {
      const result = loadHostProfile({ pluginRoot: repoRoot, host });
      expect(result.complete).toBe(true);
      expect(result.profile).toMatchObject({
        schema_version: 1,
        host,
        projection_targets: [expect.objectContaining({ managed: true })]
      });
      expect(JSON.stringify(result.profile)).not.toMatch(/verified|supporting_evidence_ids|last_verified_at/);
    }
  });

  test("dry-run projection is deterministic and writes no files", () => {
    const workspaceRoot = fixtureWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot, pluginRoot: repoRoot });
    const profile = loadHostProfile({ pluginRoot: repoRoot, host: "claude" }).profile;
    if (!profile) {
      throw new Error("expected claude profile");
    }

    const first = projectHostFiles({ context, profile, mode: "dry-run" });
    const second = projectHostFiles({ context, profile, mode: "dry-run" });

    expect(first).toEqual(second);
    expect(first.operations).toEqual([
      expect.objectContaining({
        action: "create",
        path: ".claude/use-cases-plugin.md"
      }),
      expect.objectContaining({
        action: "create",
        path: ".presentation-skills-projection.json"
      })
    ]);
    expect(existsSync(join(workspaceRoot, ".claude", "use-cases-plugin.md"))).toBe(false);
    expect(existsSync(join(workspaceRoot, ".presentation-skills-projection.json"))).toBe(false);
  });

  test("write projection is idempotent, manifest-backed, and thin", () => {
    const workspaceRoot = fixtureWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot, pluginRoot: repoRoot });
    const profile = loadHostProfile({ pluginRoot: repoRoot, host: "claude" }).profile;
    if (!profile) {
      throw new Error("expected claude profile");
    }

    const first = projectHostFiles({ context, profile, mode: "write" });
    const second = projectHostFiles({ context, profile, mode: "write" });
    const stub = readFileSync(join(workspaceRoot, ".claude", "use-cases-plugin.md"), "utf8");
    const manifest = JSON.parse(readFileSync(join(workspaceRoot, ".presentation-skills-projection.json"), "utf8"));

    expect(first.operations.some((operation) => operation.action === "create")).toBe(true);
    expect(second.operations.every((operation) => operation.action === "skip_unchanged")).toBe(true);
    expect(stub).toContain("presentation-skills:managed");
    expect(stub).toContain(".agents/skills");
    expect(stub).not.toContain("## Live Run Rules");
    expect(manifest).toMatchObject({
      host: "claude",
      surface: "claude.cli",
      generated_files: [expect.objectContaining({ path: ".claude/use-cases-plugin.md" })]
    });
  });

  test("doctor and conformance separate expected, installed, static, and evidence-verified status", () => {
    const workspaceRoot = fixtureWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot, pluginRoot: repoRoot });
    const profile = loadHostProfile({ pluginRoot: repoRoot, host: "codex" }).profile;
    if (!profile) {
      throw new Error("expected codex profile");
    }

    const doctor = runHostDoctor({ context, profile });
    expect(doctor).toMatchObject({
      schema_version: 1,
      host: "codex",
      support: {
        expected: true,
        installed: false,
        static_conformant: false,
        verified_with_evidence: false,
        evidence_event_ids: []
      },
      support_status: "expected"
    });

    projectHostFiles({ context, profile, mode: "write" });
    const conformance = runHostConformance({ context, profile });
    expect(conformance).toMatchObject({
      schema_version: 1,
      host: "codex",
      status_basis: "static_conformance_only",
      evidence_event_ids: [],
      support_status: "conformant_static"
    });
  });

  test("CLI host commands expose the same status boundaries", () => {
    const workspaceRoot = fixtureWorkspace();
    const dryRun = runCli(["host", "project", "--host", "claude", "--repo", workspaceRoot, "--dry-run", "--json"]);
    expect(dryRun.status).toBe(0);
    expect(JSON.parse(dryRun.stdout)).toMatchObject({
      command: "host.project",
      ok: true,
      data: {
        mode: "dry-run",
        operations: expect.arrayContaining([expect.objectContaining({ action: "create" })])
      }
    });

    const doctor = runCli(["host", "doctor", "--host", "codex", "--repo", workspaceRoot, "--json"]);
    expect(doctor.status).toBe(0);
    expect(JSON.parse(doctor.stdout)).toMatchObject({
      command: "host.doctor",
      ok: true,
      data: {
        support: {
          expected: true,
          verified_with_evidence: false
        }
      }
    });

    const conformance = runCli(["host", "conformance", "--host", "opencode", "--repo", workspaceRoot, "--json"]);
    expect(conformance.status).toBe(0);
    expect(JSON.parse(conformance.stdout)).toMatchObject({
      command: "host.conformance",
      ok: true,
      data: {
        status_basis: "static_conformance_only",
        evidence_event_ids: []
      }
    });
  });

  test("write projection refuses a target whose parent dir symlinks outside the workspace", () => {
    // SECURITY (path traversal): the lexical '..' check passes here — the target path
    // (.claude/use-cases-plugin.md) stays in-workspace as a string. But .claude is a
    // symlink to an outside dir, so an unguarded write would land OUTSIDE the workspace.
    // The realpath-based containment check must refuse it and write nothing outside.
    const workspaceRoot = fixtureWorkspace();
    const outside = mkdtempSync(join(tmpdir(), "presentation-skills-hosts-outside-"));
    symlinkSync(outside, join(workspaceRoot, ".claude"));
    const context = resolveWorkspaceContext({ workspaceRoot, pluginRoot: repoRoot });
    const profile = loadHostProfile({ pluginRoot: repoRoot, host: "claude" }).profile;
    if (!profile) {
      throw new Error("expected claude profile");
    }

    const result = projectHostFiles({ context, profile, mode: "write" });
    expect(result.operations.some((operation) => operation.action === "refuse_unsafe_path")).toBe(true);
    expect(result.diagnostics.some((diagnostic) => diagnostic.code === "host.unsafe_projection_path")).toBe(true);
    expect(existsSync(join(outside, "use-cases-plugin.md"))).toBe(false);
  });

  test("CLI host project rejects conflicting modes", () => {
    const workspaceRoot = fixtureWorkspace();
    const result = runCli(["host", "project", "--host", "claude", "--repo", workspaceRoot, "--dry-run", "--write", "--json"]);

    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "host.project",
      ok: false,
      diagnostics: [
        expect.objectContaining({
          code: "host.project_mode_required",
          message: "Use exactly one of --dry-run, --write, or --revert."
        })
      ]
    });
  });
});

function fixtureWorkspace(): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "presentation-skills-hosts-"));
  cpSync(join(repoRoot, "examples", "host-projections"), workspaceRoot, { recursive: true, errorOnExist: false });
  rmSync(join(workspaceRoot, ".claude"), { recursive: true, force: true });
  rmSync(join(workspaceRoot, ".codex"), { recursive: true, force: true });
  rmSync(join(workspaceRoot, ".github"), { recursive: true, force: true });
  rmSync(join(workspaceRoot, ".opencode"), { recursive: true, force: true });
  rmSync(join(workspaceRoot, ".presentation-skills-projection.json"), { force: true });
  return workspaceRoot;
}

function runCli(args: string[]) {
  const build = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (build.status !== 0) {
    throw new Error(build.stderr || build.stdout);
  }
  return spawnSync("node", ["packages/ucm-cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}
