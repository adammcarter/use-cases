import { canonicalJsonSha256 } from "./canonicalJson.js";
import { BINDING_SET_HASH_ID } from "./constants.js";

// A single binding as seen by the scanner. Extra diagnostic fields (line
// numbers, byte offsets, markers, etc.) are permitted on the input but are
// deliberately excluded from the hash material per spec section 4.5.
export interface BindingSetInputMember {
  binding_slug: string;
  row_id: string;
  file_path: string;
  extent_kind: string;
  recognizer_id: string;
  span_canon_id: string;
  span_sha256: string;
  [key: string]: unknown;
}

// The exact, hashed subset of a binding (whitelist; spec section 4.5).
export interface BindingSetMaterialMember {
  binding_slug: string;
  row_id: string;
  file_path: string;
  extent_kind: string;
  recognizer_id: string;
  span_canon_id: string;
  span_sha256: string;
}

export interface BindingSetMaterial {
  schema: typeof BINDING_SET_HASH_ID;
  row_id: string;
  bindings: BindingSetMaterialMember[];
}

// Build the canonical binding-set material for a row.
//
// Included: binding_slug, row_id, file_path, extent_kind, recognizer_id,
// span_canon_id, span_sha256 (spec 4.5 rules 2-6).
// Excluded: line numbers, timestamps, proof status, marker text (rules 7-10).
// Bindings are sorted by binding_slug before hashing (rule 1).
export function buildBindingSetMaterial(
  rowId: string,
  bindings: ReadonlyArray<BindingSetInputMember>
): BindingSetMaterial {
  const sorted = [...bindings].sort((left, right) =>
    left.binding_slug < right.binding_slug
      ? -1
      : left.binding_slug > right.binding_slug
        ? 1
        : 0
  );
  return {
    schema: BINDING_SET_HASH_ID,
    row_id: rowId,
    bindings: sorted.map((binding) => ({
      binding_slug: binding.binding_slug,
      row_id: binding.row_id,
      file_path: binding.file_path,
      extent_kind: binding.extent_kind,
      recognizer_id: binding.recognizer_id,
      span_canon_id: binding.span_canon_id,
      span_sha256: binding.span_sha256
    }))
  };
}

// binding_set_hash = sha256(canonical_json(binding_set_material)).
export function computeBindingSetHash(
  rowId: string,
  bindings: ReadonlyArray<BindingSetInputMember>
): string {
  return canonicalJsonSha256(buildBindingSetMaterial(rowId, bindings));
}
