import { DEFAULT_COMPONENT_ID } from "../version.js";
import type { Diagnostic } from "./diagnostic.js";
import { createCliResult } from "./cliResult.js";
import { schemaIdForName, validateBySchemaId } from "./registry.js";

// The five Phase 1 gap schemas have no fixture file (they document in-code /
// trust-engine shapes), plus the core result envelopes, are validated
// synthetically here against representative samples — keeping the "every public
// schema is validated" conformance contract whole.
export function validateSyntheticCommonContracts(validated: Set<string>, diagnostics: Diagnostic[]) {
  const common = validateBySchemaId(schemaIdForName("common.schema.json"), {
    schema_version: 1
  });
  validated.add(schemaIdForName("common.schema.json"));
  diagnostics.push(...common.diagnostics);

  const cli = validateBySchemaId(
    schemaIdForName("cli-result.schema.json"),
    createCliResult("schema.synthetic", {})
  );
  validated.add(schemaIdForName("cli-result.schema.json"));
  diagnostics.push(...cli.diagnostics);

  const matrixValidation = validateBySchemaId(schemaIdForName("matrix-validation-result.schema.json"), {
    schema_version: 1,
    complete: true,
    valid: true,
    integrity: {
      state: "clean",
      populated: false,
      blocking_diagnostic_count: 0
    },
    files: [],
    counts: {
      files_discovered: 0,
      files_loaded: 0,
      files_excluded: 0,
      use_case_candidates: 0,
      use_cases_addressable: 0,
      use_cases_ambiguous: 0,
      use_cases_structurally_clean: 0,
      broken_references: 0
    },
    ambiguous_ids: []
  });
  validated.add(schemaIdForName("matrix-validation-result.schema.json"));
  diagnostics.push(...matrixValidation.diagnostics);

  const matrixList = validateBySchemaId(schemaIdForName("matrix-list-result.schema.json"), {
    schema_version: 1,
    complete: true,
    integrity: {
      state: "clean",
      populated: false,
      blocking_diagnostic_count: 0
    },
    use_cases: [],
    counts: {
      returned: 0,
      total_addressable: 0
    }
  });
  validated.add(schemaIdForName("matrix-list-result.schema.json"));
  diagnostics.push(...matrixList.diagnostics);

  const matrixMutation = validateBySchemaId(schemaIdForName("matrix-mutation-result.schema.json"), {
    schema_version: 1,
    operation: "upsert",
    status: "created",
    use_case_id: "synthetic.case",
    file_path: "use-cases/synthetic.yml",
    before_hash: null,
    after_hash: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    diagnostics: []
  });
  validated.add(schemaIdForName("matrix-mutation-result.schema.json"));
  diagnostics.push(...matrixMutation.diagnostics);

  const sampleEvent = {
    schema_version: 1,
    event_type: "evidence_recorded",
    event_id: "evt_evidence_synthetic",
    aggregate_id: "evidence.synthetic",
    sequence: 1,
    recorded_at: "2026-06-25T00:00:00.000Z",
    actor_type: "agent",
    host_surface: "codex.cli",
    idempotency_key: "synthetic",
    intent_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    payload: {
      evidence_kind: "manual_observation",
      use_case_ids: ["synthetic.case"],
      verifier: { type: "agent" },
      verdict: "pass",
      summary: "Synthetic evidence contract sample.",
      targets: [
        {
          use_case_id: "synthetic.case",
          use_case_semantic_hash:
            "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        }
      ],
      kind: "manual_observation",
      captured_at: "2026-06-25T00:00:00.000Z",
      result: "pass",
      producer: { type: "agent", identity: "synthetic" },
      method: { type: "reported" }
    }
  };
  const evidenceAppend = validateBySchemaId(schemaIdForName("evidence-append-result.schema.json"), {
    schema_version: 1,
    appended: true,
    event: sampleEvent,
    ledger_path: "evidence/by-id/ev/evidence.synthetic.jsonl",
    durability: "file_synced"
  });
  validated.add(schemaIdForName("evidence-append-result.schema.json"));
  diagnostics.push(...evidenceAppend.diagnostics);

  const evidenceStatus = validateBySchemaId(schemaIdForName("evidence-status-result.schema.json"), {
    schema_version: 1,
    complete: true,
    integrity: {
      state: "clean",
      unknown_scope_damage: false,
      invalid_aggregate_count: 0,
      torn_tail_count: 0
    },
    ledgers: [],
    aggregates: [],
    counts: {
      ledgers: 0,
      events_loaded: 0,
      aggregates_total: 0,
      aggregates_active: 0,
      aggregates_invalid: 0
    }
  });
  validated.add(schemaIdForName("evidence-status-result.schema.json"));
  diagnostics.push(...evidenceStatus.diagnostics);

  const samplePlan = {
    schema_version: 1,
    plan_id: "plan.synthetic.showcase",
    plan_content_hash: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    generated_at: "2026-06-25T00:00:00.000Z",
    mode: "showcase",
    complete: true,
    prepared_not_performed: true,
    readiness: "ready_with_evidence_gaps",
    integrity_acknowledgement_required: false,
    selection_method: "deterministic",
    selection_profile: {
      id: "showcase-v1",
      version: 1,
      digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    },
    input_snapshot: {
      matrix_digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      evidence_basis_digest: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      changed_paths: [],
      freshness_policy: {
        id: "default-v1",
        digest: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        evaluated_at: "2026-06-25T00:00:00.000Z"
      },
      host_surface: "codex.cli",
      workflow: {
        effective_mode: "continuous",
        source: "default",
        advisory: true
      }
    },
    workspace_snapshot: {
      repository_id: "synthetic",
      vcs: "unknown",
      head_revision: "unknown",
      dirty: false,
      working_tree_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      component_id: DEFAULT_COMPONENT_ID,
      captured_at: "2026-06-25T00:00:00.000Z"
    },
    environment_expectations: { host_surfaces: ["codex.cli"] },
    audience: "reviewer",
    timebox_seconds: 600,
    sections: [],
    selected_items: [],
    exclusions: [],
    known_gaps: []
  };
  const presentationPlanResult = validateBySchemaId(schemaIdForName("presentation-plan-result.schema.json"), {
    schema_version: 1,
    outcome: "generated",
    plan: samplePlan,
    candidate_summary: {
      considered: 0,
      eligible: 0,
      selected: 0,
      excluded: 0,
      excluded_by_reason: {}
    },
    input_integrity: {
      matrix: "clean",
      evidence: "clean"
    }
  });
  validated.add(schemaIdForName("presentation-plan-result.schema.json"));
  diagnostics.push(...presentationPlanResult.diagnostics);

  const sampleShowcaseEvent = {
    schema_version: 1,
    event_type: "observation_recorded",
    event_id: "evt_showcase_synthetic_1",
    run_id: "run.synthetic",
    aggregate_id: "run.synthetic",
    sequence: 2,
    recorded_at: "2026-06-25T00:01:00.000Z",
    actor_type: "agent",
    host_surface: "codex.cli",
    idempotency_key: "synthetic-showcase-observation",
    intent_digest: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    payload: {
      plan_item_id: "item.synthetic.case",
      observation: "Synthetic observation."
    }
  };
  const sampleShowcaseStatus = {
    schema_version: 1,
    run_id: "run.synthetic",
    complete: true,
    execution_status: "running",
    run_outcome: "incomplete",
    approval_state: "pending",
    unresolved_failure_count: 0,
    items: [
      {
        plan_item_id: "item.synthetic.case",
        verdict: "none",
        item_currency: "unknown",
        verification_state: "requirements_unmet",
        latest_observation_event_id: "evt_showcase_synthetic_1",
        latest_verdict_event_id: null
      }
    ],
    known_gaps: [],
    diagnostic_summary: {}
  };
  const showcaseStatus = validateBySchemaId(
    schemaIdForName("showcase-run-status-result.schema.json"),
    sampleShowcaseStatus
  );
  validated.add(schemaIdForName("showcase-run-status-result.schema.json"));
  diagnostics.push(...showcaseStatus.diagnostics);

  for (const fileName of [
    "showcase-start-result.schema.json",
    "showcase-event-append-result.schema.json",
    "showcase-finish-result.schema.json",
    "showcase-approval-result.schema.json"
  ]) {
    const result = validateBySchemaId(schemaIdForName(fileName), {
      schema_version: 1,
      run_id: "run.synthetic",
      appended_event_ids: ["evt_showcase_synthetic_1"],
      event: sampleShowcaseEvent,
      status: sampleShowcaseStatus
    });
    validated.add(schemaIdForName(fileName));
    diagnostics.push(...result.diagnostics);
  }

  const newSchemaSamples: Array<[string, unknown]> = [
    [
      "marker.schema.json",
      {
        marker_schema_id: "ucase-marker-v1",
        kind: "start",
        slug: "checkout.apply_coupon",
        row_id: "checkout.apply_coupon",
        suffix: null,
        role: "row",
        file: "Sources/Checkout/CouponService.swift",
        line: 3,
        column: 1
      }
    ],
    [
      "release-gate-result.schema.json",
      {
        schema_version: 1,
        policy_mode: "release",
        passed: false,
        generated_at: "2026-06-25T00:00:00.000Z",
        summary: { rows_total: 1, rows_required: 1, rows_blocked: 1 },
        blocked_row_ids: ["checkout.apply_coupon"],
        rows: [
          {
            row_id: "checkout.apply_coupon",
            status: "UNPROVEN",
            required_for_release: true,
            policy_block: true,
            reasons: ["row has a registered binding but no trusted proof event"]
          }
        ]
      }
    ],
    [
      "ledger.schema.json",
      {
        ledger_schema_id: "ucase-evidence-ledger-v1",
        append_only: true,
        entries: [
          {
            schema: "ucase-proof-event-v1",
            event_id: "evt_0001",
            created_at: "2026-06-25T00:00:00.000Z",
            row: { row_id: "checkout.apply_coupon" },
            signature: { alg: "ed25519", key_id: "ci-key-1", value: "c2lnbmF0dXJl" }
          }
        ]
      }
    ],
    [
      "keyring.schema.json",
      {
        keyring_schema_id: "ucase-public-key-registry-v1",
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAexample=\n-----END PUBLIC KEY-----\n",
            valid_from: "2026-01-01T00:00:00.000Z",
            valid_until: null,
            status: "active"
          }
        ]
      }
    ],
    [
      "authority.schema.json",
      {
        type: "ci",
        provider: "github-actions",
        repository: "use-cases-plugin/use-cases-plugin",
        ref: "refs/heads/main",
        commit: "0123456789abcdef0123456789abcdef01234567",
        run_id: "1234567890",
        actor: "octocat",
        protected_ref: null,
        event: "push"
      }
    ],
    ["mcp-tool-results.schema.json", createCliResult("matrix.status", { use_cases: [] })]
  ];
  for (const [fileName, sample] of newSchemaSamples) {
    const result = validateBySchemaId(schemaIdForName(fileName), sample);
    validated.add(schemaIdForName(fileName));
    diagnostics.push(...result.diagnostics);
  }
}
