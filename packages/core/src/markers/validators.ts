import Ajv2020Module, { type ValidateFunction } from "ajv/dist/2020.js";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  BINDING_REGISTRY_SCHEMA_ID,
  EVIDENCE_SCHEMA_ID,
  STATUS_SCHEMA_ID
} from "./constants.js";

export interface MarkerValidationError {
  instance_path: string;
  message: string;
}

export interface MarkerValidationResult {
  ok: boolean;
  errors: MarkerValidationError[];
}

const SCHEMA_FILES: Record<string, string> = {
  [BINDING_REGISTRY_SCHEMA_ID]: "binding-registry-event.schema.json",
  [EVIDENCE_SCHEMA_ID]: "proof-event.schema.json",
  [STATUS_SCHEMA_ID]: "freshness-status.schema.json"
};

let validatorCache: Map<string, ValidateFunction> | undefined;

function findSchemasDir(): string {
  const candidates = [
    fileURLToPath(new URL("./schemas/", import.meta.url)),
    fileURLToPath(new URL("../../src/markers/schemas/", import.meta.url))
  ];
  const found = candidates.find((candidate) =>
    existsSync(join(candidate, "binding-registry-event.schema.json"))
  );
  if (!found) {
    throw new Error(`unable to locate markers schemas from ${import.meta.url}`);
  }
  return found;
}

function buildValidators(): Map<string, ValidateFunction> {
  if (validatorCache) {
    return validatorCache;
  }
  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const schemasDir = findSchemasDir();
  validatorCache = new Map(
    Object.entries(SCHEMA_FILES).map(([schemaId, fileName]) => {
      const schema = JSON.parse(readFileSync(join(schemasDir, fileName), "utf8")) as Record<
        string,
        unknown
      >;
      return [schemaId, ajv.compile(schema)];
    })
  );
  return validatorCache;
}

export function validateMarkerSchema(schemaId: string, value: unknown): MarkerValidationResult {
  const validator = buildValidators().get(schemaId);
  if (!validator) {
    return {
      ok: false,
      errors: [{ instance_path: "", message: `unknown schema: ${schemaId}` }]
    };
  }
  const ok = validator(value) as boolean;
  return {
    ok,
    errors: ok
      ? []
      : (validator.errors ?? []).map((error) => ({
          instance_path: error.instancePath,
          message: error.message ?? "schema validation failed"
        }))
  };
}

export function validateBindingRegistryEvent(value: unknown): MarkerValidationResult {
  return validateMarkerSchema(BINDING_REGISTRY_SCHEMA_ID, value);
}

export function validateProofEvent(value: unknown): MarkerValidationResult {
  return validateMarkerSchema(EVIDENCE_SCHEMA_ID, value);
}

export function validateFreshnessStatus(value: unknown): MarkerValidationResult {
  return validateMarkerSchema(STATUS_SCHEMA_ID, value);
}
