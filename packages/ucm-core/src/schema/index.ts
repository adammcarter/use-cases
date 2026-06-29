import Ajv2020Module, { type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, cpSync } from "node:fs";
import { basename, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseDocument } from "yaml";

export type Diagnostic = {
  code: string;
  severity: "info" | "warning" | "error";
  message: string;
  source_path: string | null;
  json_pointer: string | null;
  source_span?: {
    start: { line: number; column: number };
    end: { line: number; column: number };
  };
  entity_id: string | null;
  related_ids: string[];
};

export type ValidationResult = {
  ok: boolean;
  diagnostics: Diagnostic[];
};

export type ParsedYamlResult =
  | { ok: true; value: unknown; diagnostics: Diagnostic[] }
  | { ok: false; value?: undefined; diagnostics: Diagnostic[] };

export type FixtureValidationResult = {
  ok: boolean;
  complete: boolean;
  diagnostics: Diagnostic[];
  validated_schema_ids: string[];
  expected_state?: unknown;
};

export type CliContext = {
  workspace_root: string;
  data_root: string;
  component_id: string;
  workspace_snapshot: {
    repository_id: string;
    vcs: "git" | "none" | "unknown";
    head_revision: string;
    dirty: boolean;
    working_tree_digest: string;
    component_id: string;
    captured_at: string;
  };
};

export type CliResult<T> = {
  schema_version: 1;
  protocol_version: 1;
  command: string;
  ok: boolean;
  complete: boolean;
  data: T;
  diagnostics: Diagnostic[];
  context: CliContext;
};

export const PUBLIC_SCHEMA_IDS = [
  "https://use-case-matrix.dev/schemas/v1/common.schema.json",
  "https://use-case-matrix.dev/schemas/v1/cli-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/use-case-file.schema.json",
  "https://use-case-matrix.dev/schemas/v1/evidence-event.schema.json",
  "https://use-case-matrix.dev/schemas/v1/demo-capsule.schema.json",
  "https://use-case-matrix.dev/schemas/v1/presentation-plan.schema.json",
  "https://use-case-matrix.dev/schemas/v1/presentation-plan-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-event.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-run-status-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-start-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-event-append-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-finish-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/showcase-approval-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/host-profile.schema.json",
  "https://use-case-matrix.dev/schemas/v1/host-status-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/workspace-config.schema.json",
  "https://use-case-matrix.dev/schemas/v1/workflow-mode.schema.json",
  "https://use-case-matrix.dev/schemas/v1/matrix-validation-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/matrix-list-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/matrix-mutation-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/evidence-append-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/evidence-status-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/migration-test-matrix-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/marker.schema.json",
  "https://use-case-matrix.dev/schemas/v1/release-gate-result.schema.json",
  "https://use-case-matrix.dev/schemas/v1/ledger.schema.json",
  "https://use-case-matrix.dev/schemas/v1/keyring.schema.json",
  "https://use-case-matrix.dev/schemas/v1/authority.schema.json",
  "https://use-case-matrix.dev/schemas/v1/mcp-tool-results.schema.json"
] as const;

const SCHEMA_FILE_NAMES = [
  "common.schema.json",
  "cli-result.schema.json",
  "use-case-file.schema.json",
  "evidence-event.schema.json",
  "demo-capsule.schema.json",
  "presentation-plan.schema.json",
  "presentation-plan-result.schema.json",
  "showcase-event.schema.json",
  "showcase-run-status-result.schema.json",
  "showcase-start-result.schema.json",
  "showcase-event-append-result.schema.json",
  "showcase-finish-result.schema.json",
  "showcase-approval-result.schema.json",
  "host-profile.schema.json",
  "host-status-result.schema.json",
  "workspace-config.schema.json",
  "workflow-mode.schema.json",
  "matrix-validation-result.schema.json",
  "matrix-list-result.schema.json",
  "matrix-mutation-result.schema.json",
  "evidence-append-result.schema.json",
  "evidence-status-result.schema.json",
  "migration-test-matrix-result.schema.json",
  "marker.schema.json",
  "release-gate-result.schema.json",
  "ledger.schema.json",
  "keyring.schema.json",
  "authority.schema.json",
  "mcp-tool-results.schema.json"
] as const;

let schemaCache: Map<string, unknown> | undefined;
let validatorCache: Map<string, ValidateFunction> | undefined;

export function getPublicSchemas(): Array<{ id: string; schema: unknown }> {
  const schemas = loadSchemas();
  return PUBLIC_SCHEMA_IDS.map((id) => ({ id, schema: schemas.get(id) }));
}

export function validatePublicSchemas(): { ok: boolean; schema_count: number; diagnostics: Diagnostic[] } {
  try {
    buildValidators();
    return {
      ok: true,
      schema_count: PUBLIC_SCHEMA_IDS.length,
      diagnostics: []
    };
  } catch (error) {
    return {
      ok: false,
      schema_count: 0,
      diagnostics: [
        diagnostic(
          "schema.compile_failed",
          error instanceof Error ? error.message : String(error),
          null
        )
      ]
    };
  }
}

export function validateBySchemaId(schemaId: string, value: unknown, sourcePath: string | null = null): ValidationResult {
  const validator = buildValidators().get(schemaId);
  if (!validator) {
    return {
      ok: false,
      diagnostics: [diagnostic("schema.unknown", `Unknown schema: ${schemaId}`, sourcePath)]
    };
  }

  const ok = validator(value);
  return {
    ok,
    diagnostics: ok ? [] : mapAjvErrors(validator.errors ?? [], sourcePath)
  };
}

export function parseYamlToJson(source: string, sourcePath: string): ParsedYamlResult {
  if (/^\s*<<\s*:/m.test(source)) {
    return {
      ok: false,
      diagnostics: [diagnostic("yaml.merge_key_rejected", "YAML merge keys are not supported.", sourcePath)]
    };
  }
  if (/(^|[\s,[{])![A-Za-z]/.test(source)) {
    return {
      ok: false,
      diagnostics: [diagnostic("yaml.custom_tag_rejected", "Custom YAML tags are not supported.", sourcePath)]
    };
  }

  const document = parseDocument(source, {
    merge: false,
    prettyErrors: false,
    schema: "core",
    uniqueKeys: true
  });
  const yamlProblems = [...document.errors, ...document.warnings];
  if (yamlProblems.length > 0) {
    return {
      ok: false,
      diagnostics: yamlProblems.map((problem) =>
        diagnostic(
          problem.code === "DUPLICATE_KEY" ? "yaml.duplicate_key" : "parse_error",
          problem.message,
          sourcePath
        )
      )
    };
  }

  return {
    ok: true,
    value: document.toJSON(),
    diagnostics: []
  };
}

export function computeSemanticHash(value: unknown): string {
  return `sha256:${createHash("sha256").update(canonicalJson(value)).digest("hex")}`;
}

export function validateFixtureWorkspace(workspacePath: string): FixtureValidationResult {
  const diagnostics: Diagnostic[] = [];
  const validated = new Set<string>();
  const useCaseIds = new Map<string, string>();
  const expectedPath = join(workspacePath, "expected.json");
  const expected = existsSync(expectedPath)
    ? (JSON.parse(readFileSync(expectedPath, "utf8")) as { expected_state?: unknown })
    : {};

  validateSyntheticCommonContracts(validated, diagnostics);

  for (const filePath of listFiles(workspacePath)) {
    const relPath = relative(workspacePath, filePath).split(sep).join("/");
    if (relPath === "expected.json") {
      continue;
    }

    const schemaId = schemaIdForFixturePath(relPath);
    const extension = extname(filePath);
    if (!schemaId && extension !== ".yml" && extension !== ".yaml") {
      continue;
    }

    if (extension === ".jsonl") {
      validateJsonLines(filePath, relPath, schemaId, validated, diagnostics);
      continue;
    }

    const parsed = parseFixtureFile(filePath, relPath);
    diagnostics.push(...parsed.diagnostics);
    if (!parsed.ok) {
      continue;
    }

    if (schemaId) {
      const result = validateBySchemaId(schemaId, parsed.value, relPath);
      validated.add(schemaId);
      diagnostics.push(...result.diagnostics);
    }

    if (schemaId === schemaIdForName("use-case-file.schema.json")) {
      collectUseCaseIds(parsed.value, relPath, useCaseIds, diagnostics);
    }
  }

  const complete = !diagnostics.some((item) => item.severity === "error");
  return {
    ok: complete,
    complete,
    diagnostics,
    validated_schema_ids: PUBLIC_SCHEMA_IDS.filter((id) => validated.has(id)),
    expected_state: expected.expected_state
  };
}

export function createCliResult<T>(
  command: string,
  data: T,
  options: {
    ok?: boolean;
    complete?: boolean;
    diagnostics?: Diagnostic[];
    workspaceRoot?: string;
    dataRoot?: string;
    componentId?: string;
  } = {}
): CliResult<T> {
  const workspaceRoot = options.workspaceRoot ?? process.cwd();
  const dataRoot = options.dataRoot ?? workspaceRoot;
  const componentId = options.componentId ?? "presentation-skills";
  return {
    schema_version: 1,
    protocol_version: 1,
    command,
    ok: options.ok ?? true,
    complete: options.complete ?? true,
    data,
    diagnostics: options.diagnostics ?? [],
    context: {
      workspace_root: workspaceRoot,
      data_root: dataRoot,
      component_id: componentId,
      workspace_snapshot: {
        repository_id: "unknown",
        vcs: "unknown",
        head_revision: "unknown",
        dirty: false,
        working_tree_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        component_id: componentId,
        captured_at: new Date(0).toISOString()
      }
    }
  };
}

export function copySchemasToDist(): void {
  const source = findSchemasDir();
  const destination = fileURLToPath(new URL("../../dist/schemas/v1/", import.meta.url));
  rmSync(destination, { recursive: true, force: true });
  mkdirSync(destination, { recursive: true });
  for (const fileName of SCHEMA_FILE_NAMES) {
    cpSync(join(source, fileName), join(destination, fileName));
  }
}

function validateSyntheticCommonContracts(validated: Set<string>, diagnostics: Diagnostic[]) {
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
      component_id: "presentation-skills",
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

  // The five Phase 1 gap schemas have no fixture file (they document in-code /
  // trust-engine shapes), so they are validated synthetically here against a
  // representative sample — keeping the "every public schema is validated"
  // conformance contract whole.
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
        repository: "use-case-matrix/presentation-skills",
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

function validateJsonLines(
  filePath: string,
  relPath: string,
  schemaId: string | undefined,
  validated: Set<string>,
  diagnostics: Diagnostic[]
) {
  if (!schemaId) {
    return;
  }
  const lines = readFileSync(filePath, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  for (const [index, line] of lines.entries()) {
    try {
      const value = JSON.parse(line) as unknown;
      const result = validateBySchemaId(schemaId, value, `${relPath}:${index + 1}`);
      validated.add(schemaId);
      diagnostics.push(...result.diagnostics);
    } catch (error) {
      diagnostics.push(
        diagnostic(
          "parse_error",
          error instanceof Error ? error.message : String(error),
          `${relPath}:${index + 1}`
        )
      );
    }
  }
}

function parseFixtureFile(filePath: string, relPath: string): ParsedYamlResult {
  const extension = extname(filePath);
  const source = readFileSync(filePath, "utf8");
  if (extension === ".json") {
    try {
      return { ok: true, value: JSON.parse(source) as unknown, diagnostics: [] };
    } catch (error) {
      return {
        ok: false,
        diagnostics: [
          diagnostic("parse_error", error instanceof Error ? error.message : String(error), relPath)
        ]
      };
    }
  }

  return parseYamlToJson(source, relPath);
}

function collectUseCaseIds(
  value: unknown,
  relPath: string,
  seen: Map<string, string>,
  diagnostics: Diagnostic[]
) {
  if (!isRecord(value) || !Array.isArray(value.use_cases)) {
    return;
  }
  for (const useCase of value.use_cases) {
    if (!isRecord(useCase) || typeof useCase.id !== "string") {
      continue;
    }
    const previousPath = seen.get(useCase.id);
    if (previousPath) {
      diagnostics.push({
        ...diagnostic(
          "workspace.duplicate_use_case_id",
          `Use case '${useCase.id}' appears in both ${previousPath} and ${relPath}.`,
          relPath
        ),
        entity_id: useCase.id,
        related_ids: [previousPath]
      });
    } else {
      seen.set(useCase.id, relPath);
    }
  }
}

function schemaIdForFixturePath(relPath: string): string | undefined {
  if (relPath === "presentation-skills.yml") {
    return schemaIdForName("workspace-config.schema.json");
  }
  if (relPath.startsWith("workflow-modes/") || basename(relPath) === "valid-sibling.yml") {
    return schemaIdForName("workflow-mode.schema.json");
  }
  if (relPath.startsWith("use-cases/")) {
    return schemaIdForName("use-case-file.schema.json");
  }
  if (relPath.startsWith("evidence/")) {
    return schemaIdForName("evidence-event.schema.json");
  }
  if (relPath.startsWith("demo-capsules/")) {
    return schemaIdForName("demo-capsule.schema.json");
  }
  if (relPath.startsWith("presentation-plans/")) {
    return schemaIdForName("presentation-plan.schema.json");
  }
  if (relPath.startsWith("showcase-runs/")) {
    return schemaIdForName("showcase-event.schema.json");
  }
  if (relPath.startsWith("hosts/")) {
    return schemaIdForName("host-profile.schema.json");
  }
  if (relPath.startsWith("host-status/")) {
    return schemaIdForName("host-status-result.schema.json");
  }
  if (relPath.startsWith("migrations/")) {
    return schemaIdForName("migration-test-matrix-result.schema.json");
  }
  return undefined;
}

function buildValidators(): Map<string, ValidateFunction> {
  if (validatorCache) {
    return validatorCache;
  }

  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({
    allErrors: true,
    strict: true
  });
  const schemas = loadSchemas();
  for (const schema of schemas.values()) {
    ajv.addSchema(schema as Record<string, unknown>);
  }

  validatorCache = new Map(
    PUBLIC_SCHEMA_IDS.map((id) => {
      const validator = ajv.getSchema(id);
      if (!validator) {
        throw new Error(`schema did not compile: ${id}`);
      }
      return [id, validator];
    })
  );
  return validatorCache;
}

function loadSchemas(): Map<string, unknown> {
  if (schemaCache) {
    return schemaCache;
  }
  const schemasDir = findSchemasDir();
  schemaCache = new Map(
    SCHEMA_FILE_NAMES.map((fileName) => {
      const schema = JSON.parse(readFileSync(join(schemasDir, fileName), "utf8")) as {
        $id: string;
      };
      return [schema.$id, schema];
    })
  );
  return schemaCache;
}

function findSchemasDir(): string {
  const candidates = [
    fileURLToPath(new URL("../../../../schemas/v1/", import.meta.url)),
    fileURLToPath(new URL("../schemas/v1/", import.meta.url))
  ];
  const found = candidates.find((candidate) => existsSync(join(candidate, "common.schema.json")));
  if (!found) {
    throw new Error(`unable to locate schemas/v1 from ${import.meta.url}`);
  }
  return found;
}

function schemaIdForName(fileName: string): string {
  return `https://use-case-matrix.dev/schemas/v1/${fileName}`;
}

function listFiles(root: string): string[] {
  if (!existsSync(root)) {
    return [];
  }
  const entries = readdirSync(root, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files.sort();
}

function mapAjvErrors(errors: ErrorObject[], sourcePath: string | null): Diagnostic[] {
  return errors.map((error) => {
    const missingProperty =
      error.keyword === "required" && isRecord(error.params)
        ? String(error.params.missingProperty)
        : null;
    return diagnostic(
      diagnosticCode(error, missingProperty),
      error.message ?? "Schema validation failed.",
      sourcePath,
      error.instancePath || null
    );
  });
}

function diagnosticCode(error: ErrorObject, missingProperty: string | null): string {
  if (error.keyword === "additionalProperties") {
    return "additional_property";
  }
  if (error.keyword === "enum" || error.keyword === "const") {
    return "enum.invalid_value";
  }
  if (missingProperty === "schema_version") {
    return "schema_version.required";
  }
  if (missingProperty === "observable_outcomes") {
    return "use_case.observable_outcomes.required";
  }
  if (missingProperty === "approval_policy") {
    return "approval_policy.required";
  }
  if (missingProperty) {
    return `${missingProperty}.required`;
  }
  return `schema.${error.keyword}`;
}

function diagnostic(
  code: string,
  message: string,
  sourcePath: string | null,
  jsonPointer: string | null = null
): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: jsonPointer,
    entity_id: null,
    related_ids: []
  };
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, item]) => item !== undefined)
    .sort(([left], [right]) => left.localeCompare(right));
  return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`).join(",")}}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
