// Diagnostic types + the canonical factory. This is the leaf of the schema
// module: nothing here imports a sibling, so everything else can depend on it.

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

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// Canonical factory for {@link Diagnostic} objects.
//
// This is the single source for the ~13 previously-duplicated local
// `diagnostic()` helpers that had drifted across the codebase. The dominant
// shape is positional `(code, message, sourcePath?, entityId?, relatedIds?)`
// with `severity` defaulting to "error" and `json_pointer` to null.
//
// The two outliers are adapted at their call sites via object spread:
//   - hosts/conformanceStatus needs a non-error severity ("warning")
//   - schema/validate + registry need a json_pointer / extra fields
// Both override the relevant field on top of the object this returns.
export function diagnostic(
  code: string,
  message: string,
  sourcePath: string | null = null,
  entityId: string | null = null,
  relatedIds: string[] = []
): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: entityId,
    related_ids: relatedIds
  };
}
