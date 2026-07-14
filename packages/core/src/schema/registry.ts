import Ajv2020Module, { type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import { existsSync, mkdirSync, readFileSync, rmSync, cpSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { diagnostic, isRecord, type Diagnostic, type ValidationResult } from "./diagnostic.js";

export const PUBLIC_SCHEMA_IDS = [
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
  "https://use-cases.dev/schemas/v1/approval-token.schema.json",
  "https://use-cases.dev/schemas/v1/mcp-tool-results.schema.json"
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
  "approval-token.schema.json",
  "mcp-tool-results.schema.json"
] as const;

let schemaCache: Map<string, unknown> | undefined;
let validatorCache: Map<string, ValidateFunction> | undefined;

export function schemaIdForName(fileName: string): string {
  return `https://use-cases.dev/schemas/v1/${fileName}`;
}

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
    diagnostics: ok ? [] : mapAjvErrors(validator.errors ?? [], sourcePath, value)
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

function mapAjvErrors(
  errors: ErrorObject[],
  sourcePath: string | null,
  data?: unknown
): Diagnostic[] {
  return errors.map((error) => {
    const missingProperty =
      error.keyword === "required" && isRecord(error.params)
        ? String(error.params.missingProperty)
        : null;
    return {
      ...diagnostic(
        diagnosticCode(error, missingProperty),
        locatedMessage(error, missingProperty),
        sourcePath,
        entityIdFor(error, data)
      ),
      json_pointer: error.instancePath || null
    };
  });
}

// Name the offending FIELD in the message. AJV's raw message ("must be equal to
// one of the allowed values") describes the rule, not the thing that broke it —
// so a reader with 36 rows across 3 files gets a scavenger hunt. The field name
// is already sitting in the instancePath; put it where it will be read.
function locatedMessage(error: ErrorObject, missingProperty: string | null): string {
  const base = enumMessage(error);
  // `required` errors already name the property in AJV's own message.
  const field = missingProperty ?? fieldNameOf(error.instancePath);
  return field === null ? base : `${field}: ${base}`;
}

// The last non-numeric segment of a JSON pointer — `/use_cases/3/value_tier`
// yields `value_tier`. Array indices are skipped: they are position, not field.
function fieldNameOf(instancePath: string): string | null {
  const segments = instancePath.split("/").filter((segment) => segment !== "");
  for (let index = segments.length - 1; index >= 0; index -= 1) {
    const segment = segments[index];
    if (!/^\d+$/.test(segment)) {
      return segment;
    }
  }
  return null;
}

// Resolve the use-case row a diagnostic belongs to, so the reader is told WHICH
// row is broken instead of being handed a bare pointer. Best-effort by design: a
// document that does not have `/use_cases/<n>/id` simply yields null.
function entityIdFor(error: ErrorObject, data: unknown): string | null {
  const match = /^\/use_cases\/(\d+)(\/|$)/.exec(error.instancePath);
  if (!match || !isRecord(data)) {
    return null;
  }
  const rows = data.use_cases;
  if (!Array.isArray(rows)) {
    return null;
  }
  const row = rows[Number(match[1])];
  if (!isRecord(row) || typeof row.id !== "string") {
    return null;
  }
  return row.id;
}

function enumMessage(error: ErrorObject): string {
  const base = error.message ?? "Schema validation failed.";
  if (error.keyword !== "enum" || !isRecord(error.params)) {
    return base;
  }
  const allowedValues = error.params.allowedValues;
  if (!Array.isArray(allowedValues) || allowedValues.length === 0) {
    return base;
  }
  return `${base} (allowed: ${allowedValues.join(", ")})`;
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
