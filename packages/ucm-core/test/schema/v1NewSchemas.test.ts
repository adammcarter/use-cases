// Conformance tests for the five v1 schema gaps closed in Phase 1:
//   marker, release-gate-result, ledger, keyring, mcp-tool-results.
//
// Each schema must: compile in the public AJV registry, validate its own
// embedded example(s), and reject a deliberately invalid fixture. We also assert
// each new schema is registered in PUBLIC_SCHEMA_IDS and gets copied to dist by
// copySchemasToDist().
import Ajv2020Module, { type ValidateFunction } from "ajv/dist/2020.js";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { PUBLIC_SCHEMA_IDS, copySchemasToDist } from "../../src/schema/index.js";

const SCHEMAS_DIR = fileURLToPath(new URL("../../../../schemas/v1/", import.meta.url));

function loadAllSchemas(): Array<Record<string, unknown> & { $id: string }> {
  return readdirSync(SCHEMAS_DIR)
    .filter((name) => name.endsWith(".schema.json"))
    .map((name) => JSON.parse(readFileSync(join(SCHEMAS_DIR, name), "utf8")) as Record<string, unknown> & { $id: string });
}

function buildRegistry(): { validatorFor: (id: string) => ValidateFunction; byName: (name: string) => Record<string, unknown> & { $id: string } } {
  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const schemas = loadAllSchemas();
  for (const schema of schemas) {
    ajv.addSchema(schema);
  }
  return {
    validatorFor(id: string) {
      const validator = ajv.getSchema(id);
      if (!validator) {
        throw new Error(`schema did not compile: ${id}`);
      }
      return validator;
    },
    byName(name: string) {
      const schema = schemas.find((s) => s.$id.endsWith(`/${name}`));
      if (!schema) {
        throw new Error(`schema not found: ${name}`);
      }
      return schema;
    }
  };
}

const NEW_SCHEMAS = [
  "marker.schema.json",
  "release-gate-result.schema.json",
  "ledger.schema.json",
  "keyring.schema.json",
  "mcp-tool-results.schema.json"
] as const;

const ID_BASE = "https://use-case-matrix.dev/schemas/v1/";

describe("v1 new schemas (5 gaps closed)", () => {
  const registry = buildRegistry();

  test.each(NEW_SCHEMAS)("%s is registered in PUBLIC_SCHEMA_IDS", (name) => {
    expect(PUBLIC_SCHEMA_IDS as readonly string[]).toContain(`${ID_BASE}${name}`);
  });

  test.each(NEW_SCHEMAS)("%s compiles and validates its own examples", (name) => {
    const schema = registry.byName(name);
    const validate = registry.validatorFor(schema.$id);
    const examples = (schema.examples as unknown[]) ?? [];
    expect(examples.length).toBeGreaterThan(0);
    for (const example of examples) {
      const ok = validate(example);
      if (!ok) {
        throw new Error(`${name} example failed: ${JSON.stringify(validate.errors)}`);
      }
      expect(ok).toBe(true);
    }
  });

  // --- per-schema invalid fixtures ---

  test("marker rejects an out-of-enum kind", () => {
    const validate = registry.validatorFor(`${ID_BASE}marker.schema.json`);
    expect(
      validate({
        marker_schema_id: "ucase-marker-v1",
        kind: "begin",
        slug: "checkout.apply_coupon",
        row_id: "checkout.apply_coupon",
        suffix: null,
        role: "row",
        file: "a.swift",
        line: 1,
        column: 1
      })
    ).toBe(false);
  });

  test("marker rejects a malformed slug", () => {
    const validate = registry.validatorFor(`${ID_BASE}marker.schema.json`);
    expect(
      validate({
        marker_schema_id: "ucase-marker-v1",
        kind: "start",
        slug: "Bad Slug!",
        row_id: "checkout.apply_coupon",
        suffix: null,
        role: "row",
        file: "a.swift",
        line: 1,
        column: 1
      })
    ).toBe(false);
  });

  test("release-gate-result rejects a missing summary", () => {
    const validate = registry.validatorFor(`${ID_BASE}release-gate-result.schema.json`);
    expect(
      validate({
        schema_version: 1,
        policy_mode: "release",
        passed: true,
        generated_at: "2026-06-28T12:10:00Z",
        blocked_row_ids: [],
        rows: []
      })
    ).toBe(false);
  });

  test("ledger rejects an entry that is not a proof event", () => {
    const validate = registry.validatorFor(`${ID_BASE}ledger.schema.json`);
    expect(
      validate({
        ledger_schema_id: "ucase-evidence-ledger-v1",
        append_only: true,
        entries: [{ schema: "not-a-proof-event", event_id: "x", created_at: "t", row: { row_id: "r" }, signature: { alg: "ed25519", key_id: "k", value: "v" } }]
      })
    ).toBe(false);
  });

  test("ledger rejects append_only:false", () => {
    const validate = registry.validatorFor(`${ID_BASE}ledger.schema.json`);
    expect(
      validate({ ledger_schema_id: "ucase-evidence-ledger-v1", append_only: false, entries: [] })
    ).toBe(false);
  });

  test("keyring rejects a non-ed25519 algorithm", () => {
    const validate = registry.validatorFor(`${ID_BASE}keyring.schema.json`);
    expect(
      validate({
        keyring_schema_id: "ucase-public-key-registry-v1",
        keys: [
          {
            key_id: "k",
            algorithm: "rsa",
            public_key: "pem",
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: null,
            status: "active"
          }
        ]
      })
    ).toBe(false);
  });

  test("mcp-tool-results rejects a value missing the CLI envelope context", () => {
    const validate = registry.validatorFor(`${ID_BASE}mcp-tool-results.schema.json`);
    expect(
      validate({
        schema_version: 1,
        protocol_version: 1,
        command: "matrix.status",
        ok: true,
        complete: true,
        data: {},
        diagnostics: []
      })
    ).toBe(false);
  });

  test("copySchemasToDist copies every new schema to dist", () => {
    copySchemasToDist();
    const distDir = fileURLToPath(new URL("../../dist/schemas/v1/", import.meta.url));
    for (const name of NEW_SCHEMAS) {
      expect(existsSync(join(distDir, name))).toBe(true);
    }
  });
});
