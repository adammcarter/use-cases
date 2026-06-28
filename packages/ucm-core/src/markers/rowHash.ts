import { computeSemanticHash } from "../schema/index.js";

// Row hash adapter.
//
// Reuses the existing semantic-hash algorithm (computeSemanticHash) rather than
// reinventing one, so a row's freshness hash stays consistent with the rest of
// the system. Returns "sha256:<hex>".
export function computeRowHash(row: unknown): string {
  return computeSemanticHash(row);
}
