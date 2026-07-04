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
      "capsule.demos.adhoc_release_demo",
      "capsule.demos.persisted_smoke_runbook",
      "capsule.demos.runbook_not_proof",
      "capsule.demos.runner_command_safety",
      "capsule.demos.stale_reference_warning",
      "capsule.live_runner.scripted",
      "diagnostics.contracts.cli_self_documents",
      "diagnostics.contracts.identity_consistency",
      "diagnostics.contracts.missing_build_hint",
      "diagnostics.contracts.root_resolution",
      "diagnostics.contracts.schema_contract_surface",
      "evidence.core.record",
      "evidence.ledger.append_only_corrections",
      "evidence.ledger.assurance_and_freshness",
      "evidence.ledger.crash_durable_ledger_writes",
      "evidence.ledger.damaged_ledger_replay",
      "evidence.ledger.product_proof_map",
      "evidence.ledger.untrusted_content_boundary",
      "hosts.profiles.bootstrap_autoinject",
      "hosts.profiles.bootstrap_visibility",
      "hosts.profiles.first_class_profile_set",
      "hosts.profiles.live_activation_caveat",
      "hosts.profiles.projection_checksum_integrity",
      "hosts.profiles.smoke_signal_resilience",
      "hosts.profiles.surface_limitations",
      "hosts.projections.all",
      "hosts.projections.static_conformance",
      "lifecycle.loop.agent_matrix_stewardship",
      "lifecycle.loop.continuous_loop",
      "lifecycle.loop.opt_out_or_tiny_change",
      "lifecycle.loop.user_feature_printout",
      "lifecycle.loop.workflow_modes",
      "matrix.core.mutate",
      "matrix.core.validate",
      "matrix.product.claim_guardrails",
      "matrix.product.coverage_by_value_and_journey",
      "matrix.product.integrity_degraded_nonfatal",
      "matrix.product.product_inventory",
      "matrix.product.sharded_human_readable_files",
      "matrix.product.status_summary",
      "mcp.surface.approval_request_only",
      "mcp.surface.cli_contract_transport",
      "mcp.surface.declared_tool_schemas",
      "mcp.surface.domain_results_not_transport_failures",
      "mcp.surface.write_gating",
      "mcp.use_case_mutation.safe",
      "mcp.wrapper.parity",
      "migration.importer.human_review_activation",
      "migration.importer.no_legacy_pass_as_proof",
      "migration.importer.reviewable_draft_import",
      "migration.importer.source_traceability",
      "migration.test_matrix.draft",
      "planning.cards.audience_timebox_fit",
      "planning.cards.partial_matrix_warning",
      "planning.cards.prepared_not_performed",
      "planning.cards.showcase_selection",
      "planning.cards.walkthrough_coverage",
      "release.acceptance.packaged_scenario_sweep",
      "release.ci_gate.sequential",
      "release.package.installable_artifact",
      "release.proof.clean_snapshot",
      "release.proof.documentation_claim_precision",
      "release.proof.self_dogfood_evidence_bundle",
      "release.proof.version_manifest_alignment",
      "roadmap.deferred.advanced_monorepo_scoping",
      "roadmap.deferred.behavioral_host_evals",
      "roadmap.deferred.ci_authority_adapters",
      "roadmap.deferred.destructive_secret_purge",
      "roadmap.deferred.direct_user_approval_write",
      "roadmap.deferred.freshness_hard_gate_auto_selection",
      "roadmap.deferred.git_diff_auto_mapping",
      "roadmap.deferred.host_projection_conformance_tools",
      "roadmap.deferred.human_readable_trust_output",
      "roadmap.deferred.multi_machine_runner",
      "roadmap.deferred.refactor_tolerant_spans",
      "roadmap.deferred.registry_publish_channel",
      "roadmap.deferred.signed_audit_log",
      "roadmap.deferred.trusted_host_confirmation_path",
      "roadmap.deferred.v1_contract_freeze",
      "showcase.flow.approval_authority_boundary",
      "showcase.flow.control_modes",
      "showcase.flow.failure_decisions",
      "showcase.flow.live_acceptance_flow",
      "showcase.flow.revision_epoch_staleness",
      "showcase.flow.status_separation",
      "showcase.live.user_signoff",
      "skills.assets.asset_validation",
      "skills.assets.degraded_assets"
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
