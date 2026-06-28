import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../packages/ucm-core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");

describe("P10 TEST-MATRIX migration", () => {
  test("dry-run creates a reviewable report without laundering old proof", () => {
    build();
    const fixture = fixtureWorkspace();
    const result = runCli([
      "migrate",
      "test-matrix",
      "--repo",
      fixture,
      "--source",
      "TEST-MATRIX.md",
      "--dry-run",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const envelope = JSON.parse(result.stdout);
    expect(envelope).toMatchObject({
      command: "migrate.test-matrix",
      ok: true,
      data: {
        mode: "dry_run",
        summary: {
          rows_seen: 3,
          files_written: 0
        },
        drafts: [
          expect.objectContaining({
            output_path: "use-cases/_migrated/auth.yml",
            feature_id: "migrated.auth",
            use_case_ids: expect.arrayContaining(["migrated.auth.auth-1"])
          })
        ],
        warnings: expect.arrayContaining([
          expect.objectContaining({ code: "old_status_not_evidence" }),
          expect.objectContaining({ code: "legacy_evidence_not_imported" }),
          expect.objectContaining({ code: "legacy_approval_not_imported" }),
          expect.objectContaining({ code: "missing_expected_outcome" })
        ])
      }
    });
    expect(
      validateBySchemaId("https://use-case-matrix.dev/schemas/v1/migration-test-matrix-result.schema.json", envelope.data)
    ).toMatchObject({ ok: true });
    expect(JSON.stringify(envelope)).not.toMatch(/evidence_recorded|approval_recorded|verified_with_evidence/);
    expect(existsSync(join(fixture, "use-cases", "_migrated"))).toBe(false);
    expect(existsSync(join(fixture, "evidence"))).toBe(false);
  });

  test("malformed markdown produces a report and review warnings instead of crashing", () => {
    build();
    const fixture = fixtureWorkspace();
    const result = runCli([
      "migrate",
      "test-matrix",
      "--repo",
      fixture,
      "--source",
      "MALFORMED.md",
      "--dry-run",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const envelope = JSON.parse(result.stdout);
    expect(envelope).toMatchObject({
      command: "migrate.test-matrix",
      ok: true,
      complete: false,
      data: {
        summary: {
          rows_seen: 0,
          rows_needing_review: 0
        },
        warnings: expect.arrayContaining([
          expect.objectContaining({ code: "no_tables_found" })
        ])
      }
    });
  });

  test("write mode writes only migrated use-case YAML and validates it", () => {
    build();
    const fixture = fixtureWorkspace();
    const result = runCli([
      "migrate",
      "test-matrix",
      "--repo",
      fixture,
      "--source",
      "TEST-MATRIX.md",
      "--out",
      "use-cases/_migrated",
      "--write",
      "--json"
    ]);

    expect(result.status).toBe(0);
    const envelope = JSON.parse(result.stdout);
    expect(envelope.data.summary.files_written).toBe(1);
    const migrated = join(fixture, "use-cases", "_migrated", "auth.yml");
    expect(readFileSync(migrated, "utf8")).toContain("Draft intended behavior only");
    expect(existsSync(join(fixture, "use-cases", "_migrated", ".presentation-skills-migration.json"))).toBe(true);
    expect(existsSync(join(fixture, "evidence"))).toBe(false);
    expect(existsSync(join(fixture, "showcase-runs"))).toBe(false);

    const validation = runCli(["matrix", "validate", "--repo", fixture, "--json"]);
    expect(validation.status).toBe(0);
    expect(JSON.parse(validation.stdout).complete).toBe(true);
  });

  test("unsafe output path is rejected before writing", () => {
    build();
    const fixture = fixtureWorkspace();
    const result = runCli([
      "migrate",
      "test-matrix",
      "--repo",
      fixture,
      "--source",
      "TEST-MATRIX.md",
      "--out",
      "../outside",
      "--write",
      "--json"
    ]);

    expect(result.status).toBe(4);
    expect(JSON.parse(result.stdout)).toMatchObject({
      command: "migrate.test-matrix",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "migration_unsafe_output_path" })]
    });
    expect(existsSync(resolve(fixture, "../outside"))).toBe(false);
  });
});

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
  return spawnSync("node", ["packages/ucm-cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8"
  });
}

function fixtureWorkspace(): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), "presentation-skills-migration-"));
  cpSync(join(repoRoot, "tests/fixtures/workspaces/test-matrix-source"), workspaceRoot, { recursive: true });
  return workspaceRoot;
}
