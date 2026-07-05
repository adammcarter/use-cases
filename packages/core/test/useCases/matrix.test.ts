import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import { queryUseCases } from "../../src/useCases/query.js";
import { resolveWorkspaceContext } from "../../src/roots.js";

const repoRoot = resolve(import.meta.dirname, "../../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

describe("P2 use-case matrix loader", () => {
  test("loads a clean use-case matrix with source provenance and semantic hashes", () => {
    const context = resolveWorkspaceContext({
      workspaceRoot: join(fixturesRoot, "minimal-valid")
    });
    const snapshot = loadUseCaseMatrix({ context });

    expect(snapshot.complete).toBe(true);
    expect(snapshot.integrity).toMatchObject({
      state: "clean",
      populated: true,
      blockingDiagnosticCount: 0
    });
    expect(snapshot.counts).toMatchObject({
      files_discovered: 1,
      files_loaded: 1,
      use_case_candidates: 1,
      use_cases_addressable: 1,
      use_cases_ambiguous: 0,
      use_cases_structurally_clean: 1
    });
    expect(snapshot.diagnostics).toEqual([]);
    expect(snapshot.addressableUseCases).toHaveLength(1);
    expect(snapshot.addressableUseCases[0]).toMatchObject({
      value: {
        id: "auth.login.success",
        title: "Successful login",
        value_tier: "critical"
      },
      source: {
        path: "use-cases/auth-login.yml",
        jsonPointer: "/use_cases/0"
      }
    });
    expect(snapshot.addressableUseCases[0]?.semanticHash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(snapshot.addressableUseCases[0]).not.toHaveProperty("verified");
  });

  test("loads pinned workspace approval_trust from use-cases.yml", () => {
    const workspaceRoot = mkdtempSync(join(tmpdir(), "use-cases-approval-trust-"));
    const useCasesRoot = join(workspaceRoot, "use-cases");
    mkdirSync(useCasesRoot, { recursive: true });
    writeFileSync(
      join(workspaceRoot, "use-cases.yml"),
      [
        "schema_version: 1",
        "workspace_id: approval.trust.fixture",
        "data_root: .",
        "use_cases_dir: use-cases",
        "evidence_dir: evidence",
        "demo_capsules_dir: demo-capsules",
        "showcase_runs_dir: showcase-runs",
        "component_id: approval-trust",
        "approval_trust:",
        "  public_keys:",
        "    - key_id: human-key-1",
        "      algorithm: ed25519",
        "      public_key: pinned-public-key",
        "      valid_from: 2026-01-01T00:00:00Z",
        "      valid_until: null",
        "      status: active",
        "      max_assurance_tier: trusted_host_user_presence",
        ""
      ].join("\n"),
      "utf8"
    );
    writeFileSync(join(useCasesRoot, "valid.yml"), validUseCaseYaml("auth.login.approval_trust"));

    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({ workspaceRoot })
    });

    expect(snapshot.approvalTrust).toEqual({
      keyring_path: undefined,
      keyring: undefined,
      public_keys: [
        {
          key_id: "human-key-1",
          algorithm: "ed25519",
          public_key: "pinned-public-key",
          valid_from: "2026-01-01T00:00:00Z",
          valid_until: null,
          status: "active",
          max_assurance_tier: "trusted_host_user_presence"
        }
      ]
    });
  });

  test("keeps valid siblings loaded when another use-case YAML file is damaged", () => {
    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({
        workspaceRoot: join(fixturesRoot, "damaged-yaml")
      })
    });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.integrity.state).toBe("partial");
    expect(snapshot.addressableUseCases.map((item) => item.value.id)).toEqual([
      "auth.login.damage_sibling"
    ]);
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "parse_error",
        severity: "error",
        source_path: "use-cases/malformed-use-case.yml"
      })
    );
  });

  test("marks every duplicate use-case ID ambiguous and keeps it out of addressable results", () => {
    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({
        workspaceRoot: join(fixturesRoot, "duplicate-ids")
      })
    });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.integrity.state).toBe("unusable");
    expect(snapshot.candidates).toHaveLength(2);
    expect(snapshot.addressableUseCases).toHaveLength(0);
    expect(snapshot.ambiguousUseCaseIds).toEqual([
      {
        entity_kind: "use_case",
        id: "auth.login.success",
        source_paths: ["use-cases/auth-login-a.yml", "use-cases/auth-login-b.yml"]
      }
    ]);
    expect(snapshot.resolveUseCase("auth.login.success")).toMatchObject({
      kind: "ambiguous",
      id: "auth.login.success"
    });
  });

  test("reports broken references without making the source use case unaddressable", () => {
    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({
        workspaceRoot: join(fixturesRoot, "broken-reference")
      })
    });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.addressableUseCases.map((item) => item.value.id)).toEqual([
      "auth.login.with_reference"
    ]);
    expect(snapshot.resolveUseCase("auth.login.with_reference")).toMatchObject({
      kind: "resolved"
    });
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "broken_reference",
        source_path: "use-cases/auth-login.yml",
        entity_id: "auth.login.with_reference",
        related_ids: ["auth.login.missing"]
      })
    );
  });

  test("rejects symlinks under use-cases while loading valid siblings", () => {
    const workspaceRoot = mkdtempSync(join(tmpdir(), "use-cases-p2-"));
    const useCasesRoot = join(workspaceRoot, "use-cases");
    const outsideRoot = mkdtempSync(join(tmpdir(), "use-cases-outside-"));
    mkdirSync(useCasesRoot, { recursive: true });
    writeFileSync(join(useCasesRoot, "valid.yml"), validUseCaseYaml("auth.login.valid"));
    writeFileSync(join(outsideRoot, "escape.yml"), validUseCaseYaml("auth.login.escape"));
    symlinkSync(join(outsideRoot, "escape.yml"), join(useCasesRoot, "escape.yml"));

    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({ workspaceRoot })
    });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.addressableUseCases.map((item) => item.value.id)).toEqual([
      "auth.login.valid"
    ]);
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "symlink_rejected",
        source_path: "use-cases/escape.yml"
      })
    );
  });
});

describe("P2 use-case matrix queries", () => {
  test("filters addressable use cases deterministically by value, host, tags, and changed paths", () => {
    const snapshot = loadUseCaseMatrix({
      context: resolveWorkspaceContext({
        workspaceRoot: join(fixturesRoot, "minimal-valid")
      })
    });

    const matched = queryUseCases(snapshot, {
      valueTiers: ["critical"],
      hostSurfaces: ["codex.cli"],
      tagsAll: ["auth"],
      changedPaths: ["src/auth/login.ts"]
    });
    const unmatched = queryUseCases(snapshot, {
      valueTiers: ["critical"],
      hostSurfaces: ["opencode.cli"],
      changedPaths: ["src/auth/login.ts"]
    });

    expect(matched.map((item) => item.value.id)).toEqual(["auth.login.success"]);
    expect(unmatched).toEqual([]);
  });
});

function validUseCaseYaml(id: string): string {
  return [
    "schema_version: 1",
    "feature:",
    "  id: auth.login",
    "  name: Login",
    "  summary: Users can sign in.",
    "use_cases:",
    `  - id: ${id}`,
    "    title: Valid login path",
    "    lifecycle: active",
    "    value_tier: critical",
    "    journey_role: golden",
    "    usage_frequency: common",
    "    actor: registered_user",
    "    intent: Access the account area.",
    "    preconditions: [Account exists.]",
    "    trigger: Submit valid credentials.",
    "    scenarios:",
    "      - id: auth.login.valid.web",
    "        kind: steps",
    "        steps: [Submit valid credentials.]",
    "    observable_outcomes: [The account home is shown.]",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    verification_policy:",
    "      mode: none",
    "    approval_policy:",
    "      mode: none",
    ""
  ].join("\n");
}
