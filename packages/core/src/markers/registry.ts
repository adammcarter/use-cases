// Append-only binding registry: reader, validator, materializer (spec section 4).
//
// The registry (`.use-cases/bindings.jsonl`) is an append-only log of
// `binding_registered` events (amendment 2). This module turns that JSONL text
// into validated events and a materialized map, enforcing the spec 4.3
// validation rules with precise, stable error codes. Everything here is pure:
// callers pass the file text and the set of YAML row ids; no filesystem or git
// access happens in this module (the git base-ref read lives in appendOnly.ts).
import { validateBindingRegistryEvent } from "./validators.js";
import { splitSlug } from "./markerLine.js";

// One registry event (spec 4.2). Mirrors binding-registry-event.schema.json.
export interface RegistryEvent {
  schema: string;
  event_type: string;
  event_id: string;
  created_at: string;
  created_by: { tool: string; command: string; version: string };
  row_id: string;
  binding_slug: string;
  reason: string;
}

// Stable error codes for every way the registry can be invalid (spec 4.3 / 7.1).
export const RegistryErrorCode = Object.freeze({
  JSON_PARSE_ERROR: "JSON_PARSE_ERROR",
  REGISTRY_SCHEMA_INVALID: "REGISTRY_SCHEMA_INVALID",
  SLUG_PREFIX_MISMATCH: "SLUG_PREFIX_MISMATCH",
  REGISTRY_ROW_MISSING: "REGISTRY_ROW_MISSING",
  DUPLICATE_REGISTRATION: "DUPLICATE_REGISTRATION",
  SLUG_ROW_CONFLICT: "SLUG_ROW_CONFLICT"
} as const);

export type RegistryErrorCode = (typeof RegistryErrorCode)[keyof typeof RegistryErrorCode];

export interface RegistryError {
  code: RegistryErrorCode;
  line: number | null; // 1-based source line, or null when not line-bound
  message: string;
  binding_slug?: string;
  row_id?: string;
}

// One raw parsed JSONL line (value is the parsed-but-unvalidated JSON object).
export interface RegistryLine {
  line: number; // 1-based
  value: unknown;
}

export interface ReadRegistryResult {
  lines: RegistryLine[];
  errors: RegistryError[]; // JSON_PARSE_ERROR entries only
}

// Materialized registry (spec 4.3 "built by reading the JSONL in order").
export interface MaterializedRegistry {
  rowToSlugs: Map<string, Set<string>>;
  slugToRow: Map<string, string>;
}

export interface RegistryValidationResult {
  ok: boolean;
  errors: RegistryError[];
  events: RegistryEvent[]; // events that passed every rule, in order
  registry: MaterializedRegistry;
}

// Read JSONL text into one parsed value per line (spec 4.3 rule 1).
//
// A trailing newline is tolerated; whitespace-only lines are skipped so an empty
// or newline-terminated file reads cleanly. Any line that fails JSON.parse is
// reported as a JSON_PARSE_ERROR carrying its 1-based line number; the remaining
// lines are still read.
export function readBindingsJsonl(text: string): ReadRegistryResult {
  const lines: RegistryLine[] = [];
  const errors: RegistryError[] = [];
  const rawLines = text.split("\n");
  for (let i = 0; i < rawLines.length; i += 1) {
    const raw = rawLines[i];
    if (raw.trim() === "") {
      continue; // tolerate trailing newline / blank separators
    }
    const lineNo = i + 1;
    try {
      lines.push({ line: lineNo, value: JSON.parse(raw) as unknown });
    } catch (error) {
      errors.push({
        code: RegistryErrorCode.JSON_PARSE_ERROR,
        line: lineNo,
        message: `line ${lineNo} is not valid JSON: ${(error as Error).message}`
      });
    }
  }
  return { lines, errors };
}

function rowPrefixOf(bindingSlug: string): string | null {
  const parts = splitSlug(bindingSlug);
  return parts ? parts.row_id : null;
}

// Validate parsed registry lines against the schema and spec 4.3 rules, folding
// the accepted events into a materialized registry. Validation is order-sensitive
// (duplicate/conflict detection depends on the first registration of a slug).
export function validateRegistryEvents(
  read: ReadRegistryResult,
  yamlRowIds: ReadonlySet<string>
): RegistryValidationResult {
  const errors: RegistryError[] = [...read.errors];
  const events: RegistryEvent[] = [];
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();

  for (const { line, value } of read.lines) {
    // Rule 1-3: schema (covers event_type === "binding_registered" via const).
    const schemaResult = validateBindingRegistryEvent(value);
    if (!schemaResult.ok) {
      errors.push({
        code: RegistryErrorCode.REGISTRY_SCHEMA_INVALID,
        line,
        message: `registry event failed schema: ${schemaResult.errors
          .map((e) => `${e.instance_path} ${e.message}`.trim())
          .join("; ")}`
      });
      continue;
    }
    const event = value as RegistryEvent;
    const slug = event.binding_slug;
    const row = event.row_id;

    // Rule 4: binding_slug row prefix must equal row_id.
    const prefix = rowPrefixOf(slug);
    if (prefix !== row) {
      errors.push({
        code: RegistryErrorCode.SLUG_PREFIX_MISMATCH,
        line,
        message: `binding_slug ${slug} has row prefix ${prefix ?? "<invalid>"} but row_id is ${row}`,
        binding_slug: slug,
        row_id: row
      });
      continue;
    }

    // Rule 5: row_id must exist in YAML rows.
    if (!yamlRowIds.has(row)) {
      errors.push({
        code: RegistryErrorCode.REGISTRY_ROW_MISSING,
        line,
        message: `row_id ${row} is not a known YAML row`,
        binding_slug: slug,
        row_id: row
      });
      continue;
    }

    // Rules 6/8 + v1 simplification ("do not allow duplicate registration at
    // all"): a slug may be registered exactly once. Re-registering to a
    // different row is the more specific SLUG_ROW_CONFLICT.
    const existingRow = slugToRow.get(slug);
    if (existingRow !== undefined) {
      if (existingRow !== row) {
        errors.push({
          code: RegistryErrorCode.SLUG_ROW_CONFLICT,
          line,
          message: `binding_slug ${slug} already registered to ${existingRow}; cannot reassign to ${row}`,
          binding_slug: slug,
          row_id: row
        });
      } else {
        errors.push({
          code: RegistryErrorCode.DUPLICATE_REGISTRATION,
          line,
          message: `binding_slug ${slug} is already registered`,
          binding_slug: slug,
          row_id: row
        });
      }
      continue;
    }

    slugToRow.set(slug, row);
    let slugs = rowToSlugs.get(row);
    if (!slugs) {
      slugs = new Set<string>();
      rowToSlugs.set(row, slugs);
    }
    slugs.add(slug);
    events.push(event);
  }

  return {
    ok: errors.length === 0,
    errors,
    events,
    registry: { rowToSlugs, slugToRow }
  };
}

// Convenience: read then validate bindings.jsonl text in one call.
export function validateBindingsJsonl(
  text: string,
  yamlRowIds: ReadonlySet<string>
): RegistryValidationResult {
  return validateRegistryEvents(readBindingsJsonl(text), yamlRowIds);
}

// Fold already-validated events into a materialized registry (spec 4.3). Assumes
// the events passed validation (no conflict checks are repeated here).
export function materializeRegistry(events: ReadonlyArray<RegistryEvent>): MaterializedRegistry {
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();
  for (const event of events) {
    slugToRow.set(event.binding_slug, event.row_id);
    let slugs = rowToSlugs.get(event.row_id);
    if (!slugs) {
      slugs = new Set<string>();
      rowToSlugs.set(event.row_id, slugs);
    }
    slugs.add(event.binding_slug);
  }
  return { rowToSlugs, slugToRow };
}
