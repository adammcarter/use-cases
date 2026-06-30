import type { Diagnostic } from "./index.js";

// Canonical factory for {@link Diagnostic} objects.
//
// This is the single source for the ~13 previously-duplicated local
// `diagnostic()` helpers that had drifted across the codebase. The dominant
// shape is positional `(code, message, sourcePath?, entityId?, relatedIds?)`
// with `severity` defaulting to "error" and `json_pointer` to null.
//
// The two outliers are adapted at their call sites via object spread:
//   - hosts/conformanceStatus needs a non-error severity ("warning")
//   - schema/index needs a json_pointer
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
