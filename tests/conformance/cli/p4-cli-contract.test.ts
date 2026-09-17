import { cpSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");

function runCli(args: string[], cwd = repoRoot) {
  return spawnSync("node", ["packages/cli/dist/index.js", ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
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

function copyFixture(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, {
    recursive: true
  });
  return workspaceRoot;
}

describe("P4 CLI contract", () => {
  test("damaged matrix validate exits 1 but keeps ok=true and data.valid=false", () => {
    build();
    const result = runCli([
      "matrix",
      "validate",
      "--repo",
      "tests/fixtures/workspaces/damaged-yaml",
      "--json"
    ]);

    expect(result.status).toBe(1);
    expect(result.stderr).toBe("");
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({
      command: "matrix.validate",
      // Error-severity diagnostics force the envelope ok to false.
      ok: false,
      complete: false,
      data: {
        valid: false,
        integrity: {
          state: "partial"
        }
      }
    });
  });

  test("damaged matrix list is tolerant by default and integrity-blocked under strict mode", () => {
    build();
    const tolerant = runCli([
      "matrix",
      "list",
      "--repo",
      "tests/fixtures/workspaces/damaged-yaml",
      "--json"
    ]);
    expect(tolerant.status).toBe(0);
    expect(JSON.parse(tolerant.stdout)).toMatchObject({
      command: "matrix.list",
      // The process is tolerant (exit 0), but error-severity diagnostics still
      // force the envelope ok to false.
      ok: false,
      complete: false
    });

    const strict = runCli([
      "matrix",
      "list",
      "--repo",
      "tests/fixtures/workspaces/damaged-yaml",
      "--json",
      "--strict"
    ]);
    expect(strict.status).toBe(3);
    expect(JSON.parse(strict.stdout)).toMatchObject({
      command: "matrix.list",
      ok: false,
      complete: false
    });
  });

  test("explicit data-root escape exits 4 before scanning", () => {
    build();
    const result = runCli([
      "matrix",
      "validate",
      "--repo",
      "tests/fixtures/workspaces/minimal-valid",
      "--data-root",
      "../outside",
      "--json"
    ]);

    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      ok: false,
      complete: false,
      diagnostics: [expect.objectContaining({ code: "unsafe_data_root" })]
    });
  });

  test("evidence void appends a terminal event and leaves the original line intact", () => {
    build();
    const workspaceRoot = copyFixture("evidence-basic");
    const record = runCli([
      "evidence",
      "record",
      "--repo",
      workspaceRoot,
      "--use-case",
      "showcase.live.golden",
      "--kind",
      "manual_observation",
      "--result",
      "pass",
      "--idempotency-key",
      "void-test",
      "--json"
    ]);
    expect(record.status).toBe(0);
    const recordPayload = JSON.parse(record.stdout);
    const ledgerPath = join(workspaceRoot, recordPayload.data.ledger_path);
    const originalLine = readFileSync(ledgerPath, "utf8").split("\n")[0];

    const voided = runCli([
      "evidence",
      "void",
      "--repo",
      workspaceRoot,
      "--evidence",
      recordPayload.data.event.aggregate_id,
      "--expected-head",
      recordPayload.data.event.event_id,
      "--reason",
      "Wrong observation.",
      "--idempotency-key",
      "void-test-void",
      "--json"
    ]);

    expect(voided.status).toBe(0);
    expect(readFileSync(ledgerPath, "utf8").split("\n")[0]).toBe(originalLine);
    expect(JSON.parse(voided.stdout)).toMatchObject({
      command: "evidence.void",
      ok: true,
      complete: true,
      data: {
        appended: true,
        event: {
          event_type: "evidence_voided"
        }
      }
    });
  });

  test("workflow set-mode persists canonical advisory mode without weakening matrix gates", () => {
    build();
    const workspaceRoot = copyFixture("minimal-valid");
    const result = runCli([
      "workflow",
      "set-mode",
      "--repo",
      workspaceRoot,
      "--mode",
      "showcase-only",
      "--json"
    ]);

    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "workflow.set-mode",
      ok: true,
      data: {
        configured_mode: "showcase_only",
        effective_mode: "showcase_only",
        advisory: true,
        changed: true
      }
    });
    expect(readFileSync(join(workspaceRoot, "use-cases.yml"), "utf8")).toContain(
      "default_workflow_mode: showcase_only"
    );
    const matrix = runCli(["matrix", "validate", "--repo", workspaceRoot, "--json"]);
    expect(matrix.status).toBe(0);
    expect(JSON.parse(matrix.stdout).complete).toBe(true);
  });

  // The `migration` workflow mode is retired: set-mode refuses it with the same
  // envelope as any other unsupported mode, and leaves the config untouched.
  test("workflow set-mode refuses the retired migration mode", () => {
    build();
    const workspaceRoot = copyFixture("minimal-valid");
    const configPath = join(workspaceRoot, "use-cases.yml");
    const before = readFileSync(configPath, "utf8");
    const result = runCli(["workflow", "set-mode", "--repo", workspaceRoot, "--mode", "migration", "--json"]);

    expect(result.status).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "workflow.set-mode",
      ok: false,
      diagnostics: [{ code: "workflow_mode_invalid", message: "Unsupported workflow mode." }]
    });
    expect(readFileSync(configPath, "utf8")).toBe(before);
  });

  test("a workspace config naming the retired migration mode is refused by the schema", () => {
    build();
    const workspaceRoot = copyFixture("minimal-valid");
    const configPath = join(workspaceRoot, "use-cases.yml");
    writeFileSync(
      configPath,
      readFileSync(configPath, "utf8").replace(
        /^default_workflow_mode: continuous$/m,
        "default_workflow_mode: migration"
      )
    );
    expect(readFileSync(configPath, "utf8")).toContain("default_workflow_mode: migration");

    const result = runCli(["doctor", "roots", "--repo", workspaceRoot, "--json"]);
    expect(result.status).not.toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "doctor.roots",
      ok: false,
      diagnostics: [{ code: "workspace_config.schema_error", message: "Invalid use-cases.yml." }]
    });
  });

  test("doctor roots is read-only and matrix status composes matrix and evidence state", () => {
    build();
    const workspaceRoot = copyFixture("minimal-valid");
    const before = readFileSync(join(workspaceRoot, "use-cases.yml"), "utf8");
    const doctor = runCli(["doctor", "roots", "--repo", workspaceRoot, "--json"]);
    expect(doctor.status).toBe(0);
    expect(JSON.parse(doctor.stdout)).toMatchObject({
      command: "doctor.roots",
      data: {
        workspace_root: realpathSync(workspaceRoot),
        writable: true
      }
    });
    expect(readFileSync(join(workspaceRoot, "use-cases.yml"), "utf8")).toBe(before);

    const status = runCli(["matrix", "status", "--repo", workspaceRoot, "--json"]);
    expect(status.status).toBe(0);
    expect(JSON.parse(status.stdout)).toMatchObject({
      command: "matrix.status",
      ok: true,
      complete: true,
      data: {
        matrix: { complete: true },
        evidence: { complete: true }
      }
    });
  });
});
