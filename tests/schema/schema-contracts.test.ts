import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import {
  PUBLIC_SCHEMA_IDS,
  type Diagnostic,
  computeSemanticHash,
  createCliResult,
  parseYamlToJson,
  validateBySchemaId,
  validateFixtureWorkspace,
  validatePublicSchemas
} from "../../packages/core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

const expectedSchemaIds = [
  "https://use-cases.dev/schemas/v1/common.schema.json",
  "https://use-cases.dev/schemas/v1/cli-result.schema.json",
  "https://use-cases.dev/schemas/v1/use-case-file.schema.json",
  "https://use-cases.dev/schemas/v1/evidence-event.schema.json",
  "https://use-cases.dev/schemas/v1/demo-capsule.schema.json",
  "https://use-cases.dev/schemas/v1/presentation-plan.schema.json",
  "https://use-cases.dev/schemas/v1/presentation-plan-result.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-event.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-run-status-result.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-start-result.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-event-append-result.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-finish-result.schema.json",
  "https://use-cases.dev/schemas/v1/showcase-approval-result.schema.json",
  "https://use-cases.dev/schemas/v1/host-profile.schema.json",
  "https://use-cases.dev/schemas/v1/host-status-result.schema.json",
  "https://use-cases.dev/schemas/v1/workspace-config.schema.json",
  "https://use-cases.dev/schemas/v1/workflow-mode.schema.json",
  "https://use-cases.dev/schemas/v1/matrix-validation-result.schema.json",
  "https://use-cases.dev/schemas/v1/matrix-list-result.schema.json",
  "https://use-cases.dev/schemas/v1/matrix-mutation-result.schema.json",
  "https://use-cases.dev/schemas/v1/evidence-append-result.schema.json",
  "https://use-cases.dev/schemas/v1/evidence-status-result.schema.json",
  "https://use-cases.dev/schemas/v1/migration-test-matrix-result.schema.json",
  "https://use-cases.dev/schemas/v1/marker.schema.json",
  "https://use-cases.dev/schemas/v1/release-gate-result.schema.json",
  "https://use-cases.dev/schemas/v1/ledger.schema.json",
  "https://use-cases.dev/schemas/v1/keyring.schema.json",
  "https://use-cases.dev/schemas/v1/authority.schema.json",
  "https://use-cases.dev/schemas/v1/mcp-tool-results.schema.json"
];

describe("P1 schema registry", () => {
  test("exports every public v1 schema and compiles them with offline refs", () => {
    expect(PUBLIC_SCHEMA_IDS).toEqual(expectedSchemaIds);
    expect(validatePublicSchemas()).toEqual({
      ok: true,
      schema_count: expectedSchemaIds.length,
      diagnostics: []
    });
  });

  test("rejects missing schema_version and unknown properties outside extensions", () => {
    const result = validateBySchemaId(
      "https://use-cases.dev/schemas/v1/workflow-mode.schema.json",
      {
        mode: "continuous",
        unexpected: true
      }
    );

    expect(result.ok).toBe(false);
    expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(
      expect.arrayContaining(["schema_version.required", "additional_property"])
    );
  });
});

describe("P1 YAML profile", () => {
  test("rejects duplicate keys, custom tags, and merge keys before schema validation", () => {
    for (const fileName of ["duplicate-key.yml", "custom-tag.yml", "merge-key.yml"]) {
      const source = readFileSync(join(fixturesRoot, "damaged-yaml", fileName), "utf8");
      const parsed = parseYamlToJson(source, fileName);

      expect(parsed.ok).toBe(false);
      expect(parsed.diagnostics[0]).toMatchObject({
        severity: "error",
        source_path: fileName
      });
    }
  });

  test("keeps timestamp-looking YAML scalars as strings", () => {
    const parsed = parseYamlToJson(
      ["schema_version: 1", "mode: custom", "name: 2026-06-25"].join("\n"),
      "timestamp.yml"
    );

    expect(parsed.ok).toBe(true);
    expect(parsed.value).toMatchObject({
      name: "2026-06-25"
    });
  });
});

describe("P1 use-case and policy contracts", () => {
  test("validates the minimal fixture workspace", () => {
    const result = validateFixtureWorkspace(join(fixturesRoot, "minimal-valid"));

    expect(result.ok).toBe(true);
    expect(result.complete).toBe(true);
    expect(result.diagnostics).toEqual([]);
    expect(result.validated_schema_ids).toEqual(expectedSchemaIds);
  });

  test("rejects active use cases without outcomes, missing approval, or ambiguous vocabulary", () => {
    const result = validateFixtureWorkspace(join(fixturesRoot, "invalid-contracts"));

    expect(result.ok).toBe(false);
    expect(result.complete).toBe(false);
    expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(
      expect.arrayContaining([
        "use_case.observable_outcomes.required",
        "approval_policy.required",
        "enum.invalid_value"
      ])
    );
  });

  test("reports duplicate use-case IDs as workspace validation, not parse failure", () => {
    const result = validateFixtureWorkspace(join(fixturesRoot, "duplicate-ids"));

    expect(result.ok).toBe(false);
    expect(result.complete).toBe(false);
    expect(result.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "workspace.duplicate_use_case_id",
        severity: "error",
        entity_id: "auth.login.success"
      })
    );
  });
});

describe("P1 history and replay contracts", () => {
  test("showcase-basic fixture declares replay expectations for prepared and approved states", () => {
    const result = validateFixtureWorkspace(join(fixturesRoot, "showcase-basic"));

    expect(result.ok).toBe(true);
    expect(result.complete).toBe(true);
    expect(result.expected_state).toMatchObject({
      execution_status: "completed",
      outcome: "passed",
      approval_state: "approved"
    });
  });

  test("content hashes are semantic and stable across YAML formatting changes", () => {
    const compact = parseYamlToJson(
      [
        "schema_version: 1",
        "mode: continuous",
        "description: Update use cases during feature work"
      ].join("\n"),
      "compact.yml"
    );
    const spaced = parseYamlToJson(
      [
        "description: Update use cases during feature work",
        "",
        "schema_version: 1",
        "mode: continuous"
      ].join("\n"),
      "spaced.yml"
    );

    expect(compact.ok).toBe(true);
    expect(spaced.ok).toBe(true);
    expect(computeSemanticHash(compact.value)).toBe(computeSemanticHash(spaced.value));
    expect(computeSemanticHash(compact.value)).toMatch(/^sha256:[0-9a-f]{64}$/);
  });
});

describe("P2 CLI envelope ok reflects error diagnostics", () => {
  const errorDiagnostic: Diagnostic = {
    code: "schema.minItems",
    severity: "error",
    message: "must NOT have fewer than 1 items",
    source_path: "use-cases/empty-outcomes.yml",
    json_pointer: "/use_cases/0/observable_outcomes",
    entity_id: null,
    related_ids: []
  };

  test("forces ok:false when any diagnostic is error severity, even if caller passed ok:true", () => {
    const result = createCliResult(
      "matrix.validate",
      {},
      { ok: true, diagnostics: [errorDiagnostic] }
    );

    expect(result.ok).toBe(false);
  });

  test("preserves the caller-provided ok when no diagnostic is error severity", () => {
    const warningDiagnostic: Diagnostic = { ...errorDiagnostic, severity: "warning" };
    const result = createCliResult(
      "matrix.list",
      {},
      { ok: true, diagnostics: [warningDiagnostic] }
    );

    expect(result.ok).toBe(true);
  });
});

describe("P2 enum diagnostics list allowed values", () => {
  test("an invalid value_tier message names the allowed enum values", () => {
    const result = validateBySchemaId(
      "https://use-cases.dev/schemas/v1/use-case-file.schema.json",
      {
        schema_version: 1,
        use_cases: [
          {
            id: "a.b",
            title: "T",
            lifecycle: "active",
            value_tier: "nope",
            journey_role: "primary",
            usage_frequency: "daily",
            observable_outcomes: ["x"],
            approval_policy: { required: false }
          }
        ]
      }
    );

    const enumDiagnostic = result.diagnostics.find(
      (diagnostic) => diagnostic.code === "enum.invalid_value"
    );

    expect(enumDiagnostic?.message).toContain("allowed: critical, core, supporting, long_tail");
  });
});
