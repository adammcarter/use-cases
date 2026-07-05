import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { matrixValidateCommand } from "../../src/commands/matrix.js";

function workspaceWithMinimumAssuranceTier(): string {
  const root = mkdtempSync(join(tmpdir(), "ucm-matrix-validate-"));
  mkdirSync(join(root, "use-cases"), { recursive: true });
  writeFileSync(
    join(root, "use-cases.yml"),
    [
      "schema_version: 1",
      "workspace_id: matrix-validate.fixture",
      "data_root: .",
      "use_cases_dir: use-cases",
      "evidence_dir: evidence",
      "demo_capsules_dir: demo-capsules",
      "showcase_runs_dir: showcase-runs",
      "component_id: matrix-validate",
      ""
    ].join("\n"),
    "utf8"
  );
  writeFileSync(
    join(root, "use-cases/showcase.yml"),
    [
      "schema_version: 1",
      "feature:",
      "  id: showcase.live",
      "  name: Live showcase",
      "  summary: Agent performs a user-visible live demo.",
      "use_cases:",
      "  - id: showcase.live.golden",
      "    title: Agent performs verified live showcase",
      "    lifecycle: active",
      "    value_tier: critical",
      "    journey_role: golden",
      "    usage_frequency: common",
      "    actor: agent",
      "    intent: Show the product behavior directly to the user.",
      "    preconditions: [A feature run is ready to demonstrate.]",
      "    trigger: The user asks for a final showcase.",
      "    scenarios:",
      "      - id: showcase.live.golden.cli",
      "        kind: steps",
      "        steps: [Start the showcase, demonstrate the feature, record the verdict.]",
      "    observable_outcomes: [The user sees the behavior happen.]",
      "    host_applicability:",
      "      - host_surface: codex.cli",
      "        supported: true",
      "    verification_policy:",
      "      mode: requirements",
      "      requirements:",
      "        - evidence_kind: manual_observation",
      "          required_verifiers: [user]",
      "          minimum_count: 1",
      "    approval_policy:",
      "      mode: predefined",
      "      minimum_assurance_tier: same_channel_operator_confirmation",
      "      requirements:",
      "        - approver_type: user",
      "          minimum_count: 1",
      "      statement: Final acceptance requires user-visible proof.",
      ""
    ].join("\n"),
    "utf8"
  );
  return root;
}

function workspaceWithApprovalTrust(): string {
  const root = workspaceWithMinimumAssuranceTier();
  writeFileSync(
    join(root, "use-cases.yml"),
    [
      "schema_version: 1",
      "workspace_id: matrix-validate.fixture",
      "data_root: .",
      "use_cases_dir: use-cases",
      "evidence_dir: evidence",
      "demo_capsules_dir: demo-capsules",
      "showcase_runs_dir: showcase-runs",
      "component_id: matrix-validate",
      "approval_trust:",
      "  public_keys:",
      "    - key_id: human-key-1",
      "      algorithm: ed25519",
      "      public_key: pinned-public-key",
      "      valid_from: 2026-01-01T00:00:00Z",
      "      valid_until: null",
      "      status: active",
      "      assurance_tier: trusted_host_user_presence",
      ""
    ].join("\n"),
    "utf8"
  );
  return root;
}

describe("matrix validate", () => {
  test("accepts approval_policy.minimum_assurance_tier", () => {
    const workspaceRoot = workspaceWithMinimumAssuranceTier();

    const result = matrixValidateCommand.handler({
      argv: ["matrix", "validate", "--repo", workspaceRoot],
      json: true,
      flags: { repo: workspaceRoot }
    });

    expect(result.exitCode).toBe(0);
    expect((result.envelope as { complete?: boolean }).complete).toBe(true);
  });

  test("accepts workspace approval_trust config", () => {
    const workspaceRoot = workspaceWithApprovalTrust();

    const result = matrixValidateCommand.handler({
      argv: ["matrix", "validate", "--repo", workspaceRoot],
      json: true,
      flags: { repo: workspaceRoot }
    });

    expect(result.exitCode).toBe(0);
    expect((result.envelope as { complete?: boolean }).complete).toBe(true);
  });
});
