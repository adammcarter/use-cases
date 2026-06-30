// Reconcile the materialized registry against a current scan (spec section 7).
//
// For each row this computes the two reconciliation sets that feed the Phase 6
// status machine:
//   missing(row)      = registered_slugs(row) - current_marker_slugs(row)
//                       -> SUSPECT / BINDING_REMOVED (spec 7.3); the row must NOT
//                          silently disappear just because its markers are gone.
//   unregistered(row) = current_marker_slugs(row) - registered_slugs(row)
//                       -> INVALID, UNREGISTERED_BINDING (spec 7.1).
// This module derives sets only; it assigns no statuses (that is Phase 6).
import type { MaterializedRegistry } from "./registry.js";
import type { ScanResult } from "./scanner.js";

export interface RowReconciliation {
  row_id: string;
  registered_binding_slugs: string[]; // K(row), sorted
  current_binding_slugs: string[]; // C(row) slugs from scan, sorted
  missing_registered_binding_slugs: string[]; // missing(row), sorted
  unregistered_current_binding_slugs: string[]; // unregistered(row), sorted
}

// A current marker whose slug is not registered for its row (-> INVALID).
export interface UnregisteredDetection {
  binding_slug: string;
  row_id: string;
  file_path: string;
  start_line: number;
}

// A registered slug with no current marker (-> SUSPECT / BINDING_REMOVED).
export interface MissingDetection {
  binding_slug: string;
  row_id: string;
}

export interface ReconciliationResult {
  rows: RowReconciliation[];
  unregistered: UnregisteredDetection[];
  missing: MissingDetection[];
}

function sorted(values: Iterable<string>): string[] {
  return [...values].sort();
}

export function reconcileRegistryWithScan(
  registry: MaterializedRegistry,
  scan: ScanResult
): ReconciliationResult {
  // Group current scanned binding slugs by their row id.
  const currentByRow = new Map<string, Set<string>>();
  for (const binding of scan.bindings) {
    let slugs = currentByRow.get(binding.row_id);
    if (!slugs) {
      slugs = new Set<string>();
      currentByRow.set(binding.row_id, slugs);
    }
    slugs.add(binding.binding_slug);
  }

  // The row set is the union of registered rows and rows seen in the scan, so a
  // row whose markers were all removed still appears (spec 7.3).
  const rowIds = new Set<string>([...registry.rowToSlugs.keys(), ...currentByRow.keys()]);

  const rows: RowReconciliation[] = [];
  const missing: MissingDetection[] = [];
  for (const rowId of sorted(rowIds)) {
    const registered = registry.rowToSlugs.get(rowId) ?? new Set<string>();
    const current = currentByRow.get(rowId) ?? new Set<string>();

    const missingSlugs = sorted([...registered].filter((slug) => !current.has(slug)));
    const unregisteredSlugs = sorted([...current].filter((slug) => !registered.has(slug)));

    for (const slug of missingSlugs) {
      missing.push({ binding_slug: slug, row_id: rowId });
    }

    rows.push({
      row_id: rowId,
      registered_binding_slugs: sorted(registered),
      current_binding_slugs: sorted(current),
      missing_registered_binding_slugs: missingSlugs,
      unregistered_current_binding_slugs: unregisteredSlugs
    });
  }

  // Flat unregistered detections, keyed off the actual scanned binding records so
  // each carries a file path and line for a precise INVALID diagnostic.
  const unregistered: UnregisteredDetection[] = [];
  for (const binding of scan.bindings) {
    const registeredRow = registry.slugToRow.get(binding.binding_slug);
    if (registeredRow !== binding.row_id) {
      unregistered.push({
        binding_slug: binding.binding_slug,
        row_id: binding.row_id,
        file_path: binding.file_path,
        start_line: binding.start_marker.line
      });
    }
  }

  return { rows, unregistered, missing };
}
