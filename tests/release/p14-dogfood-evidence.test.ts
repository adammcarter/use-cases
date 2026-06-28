import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

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

describe("P14 v1 release dogfood evidence", () => {
  test("exposes v1 release rows in the living use-case matrix", () => {
    const listed = runCliJson(["matrix", "list", "--repo", repoRoot, "--json"]);

    expect(listed.status).toBe(0);
    expect((listed.payload.data.use_cases as Array<{ id: string }>).map((item) => item.id)).toEqual([
      "capsule.live_runner.scripted",
      "evidence.core.record",
      "hosts.projections.all",
      "hosts.projections.static_conformance",
      "matrix.core.mutate",
      "matrix.core.validate",
      "mcp.use_case_mutation.safe",
      "mcp.wrapper.parity",
      "migration.test_matrix.draft",
      "presentation_skills.capsules.adhoc_release_demo",
      "presentation_skills.capsules.multi_machine_runner",
      "presentation_skills.capsules.persisted_smoke_runbook",
      "presentation_skills.capsules.runbook_not_proof",
      "presentation_skills.capsules.runner_command_safety",
      "presentation_skills.capsules.stale_reference_warning",
      "presentation_skills.diagnostics.root_resolution",
      "presentation_skills.diagnostics.schema_contract_surface",
      "presentation_skills.evidence.append_only_corrections",
      "presentation_skills.evidence.assurance_and_freshness",
      "presentation_skills.evidence.crash_durable_ledger_writes",
      "presentation_skills.evidence.damaged_ledger_replay",
      "presentation_skills.evidence.destructive_secret_purge",
      "presentation_skills.evidence.product_proof_map",
      "presentation_skills.evidence.signed_audit_log",
      "presentation_skills.evidence.untrusted_content_boundary",
      "presentation_skills.hosts.behavioral_host_evals",
      "presentation_skills.hosts.bootstrap_visibility",
      "presentation_skills.hosts.conformance_status_truth",
      "presentation_skills.hosts.first_class_profile_set",
      "presentation_skills.hosts.live_activation_caveat",
      "presentation_skills.hosts.projection_checksum_integrity",
      "presentation_skills.hosts.smoke_signal_resilience",
      "presentation_skills.hosts.surface_limitations",
      "presentation_skills.hosts.trusted_host_confirmation_path",
      "presentation_skills.lifecycle.agent_matrix_stewardship",
      "presentation_skills.lifecycle.continuous_loop",
      "presentation_skills.lifecycle.opt_out_or_tiny_change",
      "presentation_skills.lifecycle.user_feature_printout",
      "presentation_skills.lifecycle.workflow_modes",
      "presentation_skills.matrix.advanced_monorepo_scoping",
      "presentation_skills.matrix.claim_guardrails",
      "presentation_skills.matrix.coverage_by_value_and_journey",
      "presentation_skills.matrix.git_diff_auto_mapping",
      "presentation_skills.matrix.integrity_degraded_nonfatal",
      "presentation_skills.matrix.product_inventory",
      "presentation_skills.matrix.sharded_human_readable_files",
      "presentation_skills.matrix.status_summary",
      "presentation_skills.mcp.approval_request_only",
      "presentation_skills.mcp.cli_contract_transport",
      "presentation_skills.mcp.direct_user_approval_write",
      "presentation_skills.mcp.domain_results_not_transport_failures",
      "presentation_skills.mcp.host_projection_conformance_tools",
      "presentation_skills.mcp.safe_matrix_mutation_workflow",
      "presentation_skills.mcp.write_gating",
      "presentation_skills.migration.human_review_activation",
      "presentation_skills.migration.no_legacy_pass_as_proof",
      "presentation_skills.migration.reviewable_draft_import",
      "presentation_skills.migration.source_traceability",
      "presentation_skills.planning.audience_timebox_fit",
      "presentation_skills.planning.freshness_hard_gate_auto_selection",
      "presentation_skills.planning.partial_matrix_warning",
      "presentation_skills.planning.prepared_not_performed",
      "presentation_skills.planning.showcase_selection",
      "presentation_skills.planning.walkthrough_coverage",
      "presentation_skills.release.clean_snapshot",
      "presentation_skills.release.documentation_claim_precision",
      "presentation_skills.release.installable_artifact_provenance",
      "presentation_skills.release.registry_publish_channel",
      "presentation_skills.release.self_dogfood_evidence_bundle",
      "presentation_skills.release.sequential_gate_story",
      "presentation_skills.release.version_manifest_alignment",
      "presentation_skills.showcase.approval_authority_boundary",
      "presentation_skills.showcase.control_modes",
      "presentation_skills.showcase.failure_decisions",
      "presentation_skills.showcase.live_acceptance_flow",
      "presentation_skills.showcase.revision_epoch_staleness",
      "presentation_skills.showcase.status_separation",
      "presentation_skills.skills.asset_validation",
      "presentation_skills.skills.degraded_assets",
      "release.ci_gate.sequential",
      "release.package.installable_artifact",
      "showcase.live.user_signoff"
    ]);
  });

  test("commits mechanical dogfood proof without claiming user approval", () => {
    expect(existsSync(resolve(repoRoot, "demo-capsules", "v1-release-smoke.yml"))).toBe(true);

    const capsules = runCliJson(["capsule", "list", "--repo", repoRoot, "--json"]);
    expect(capsules.status).toBe(0);
    expect(capsules.payload.data.capsules).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          capsule_id: "capsule.v1.release_smoke",
          item_count: 1
        })
      ])
    );

    const evidence = runCliJson(["evidence", "status", "--repo", repoRoot, "--json"]);
    expect(evidence.status).toBe(0);
    expect(evidence.payload.data.integrity.state).toBe("clean");

    const targetIds = new Set<string>();
    for (const aggregate of evidence.payload.data.aggregates as Array<{ target_links: Array<{ use_case_id: string }> }>) {
      for (const link of aggregate.target_links) {
        targetIds.add(link.use_case_id);
      }
    }
    expect([...targetIds].sort()).toEqual(expect.arrayContaining([
      "capsule.live_runner.scripted",
      "hosts.projections.static_conformance",
      "matrix.core.mutate",
      "release.ci_gate.sequential",
      "release.package.installable_artifact"
    ]));

    const showcase = runCliJson([
      "showcase",
      "status",
      "--repo",
      repoRoot,
      "--run",
      "run.p14_v1_release_smoke_start",
      "--json"
    ]);
    expect(showcase.status).toBe(0);
    expect(showcase.payload.data).toMatchObject({
      execution_status: "completed",
      run_outcome: "passed",
      approval_state: "not_required",
      known_gaps: []
    });
    const runLedger = readFileSync(resolve(repoRoot, "showcase-runs", "run.p14_v1_release_smoke_start", "events.jsonl"), "utf8");
    expect(runLedger).not.toContain(repoRoot);
  });
});

function runCliJson(args: string[]) {
  const result = spawnSync("node", ["packages/ucm-cli/dist/index.js", ...args], {
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
