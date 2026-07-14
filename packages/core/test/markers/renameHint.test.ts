// Field report §1.4: "Rename a symbol, break the matrix — with no path back."
//
// Renaming a bound row (the brand vocabulary changed, a type was renamed, the
// markers were renamed with it) produces two errors:
//
//   UNREGISTERED_BINDING  sidecar.tools.mcp_stage — marker is not registered
//   ROW_NOT_FOUND         sidecar.tools.mcp_stage — row is not a known use-case row
//
// "Both messages are true and useless. They describe the wreckage, not the cause
// and not the cure." The tool can SEE both halves — a registered binding whose
// marker vanished, and an unregistered marker with a suspiciously similar id —
// and made the reader work it out anyway. Now it says so.
//
// Conservative by design: it suggests a rename only when there is exactly ONE
// plausible candidate. An ambiguous case says nothing rather than guessing wrong.
import { describe, expect, test } from "vitest";
import {
  deriveFreshness,
  type CurrentBindingRecord,
  type DeriveFreshnessInput,
  type FreshnessInputRow,
  type MaterializedRegistry,
  type ScanResult
} from "../../src/markers/index.js";

const OLD_ROW = "sidecar.tools.mcp_whiteboard";
const NEW_ROW = "sidecar.tools.mcp_stage";
const OLD_SLUG = `${OLD_ROW}#handler`;
const NEW_SLUG = `${NEW_ROW}#handler`;

function makeRow(rowId: string): FreshnessInputRow {
  return {
    row_id: rowId,
    intent: "an intent",
    verification_policy: { command: "npm test" },
    approval_policy: { required_for_release: false }
  };
}

function makeBinding(slug: string, filePath: string): CurrentBindingRecord {
  const hashIndex = slug.indexOf("#");
  return {
    binding_slug: slug,
    row_id: hashIndex === -1 ? slug : slug.slice(0, hashIndex),
    suffix: hashIndex === -1 ? null : slug.slice(hashIndex + 1),
    file_path: filePath,
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v2",
    start_marker: { line: 12, column: 1 },
    end_marker: null,
    span: {
      start_line: 13,
      end_line: 27,
      start_byte: 355,
      end_byte: 849,
      sha256: `sha256:${"a".repeat(64)}`
    },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "handler", inferred: true }
  };
}

function makeRegistry(pairs: Array<[rowId: string, slug: string]>): MaterializedRegistry {
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();
  for (const [rowId, slug] of pairs) {
    slugToRow.set(slug, rowId);
    const slugs = rowToSlugs.get(rowId) ?? new Set<string>();
    slugs.add(slug);
    rowToSlugs.set(rowId, slugs);
  }
  return { rowToSlugs, slugToRow };
}

function run(input: Partial<DeriveFreshnessInput> & { rows: FreshnessInputRow[] }) {
  const scan: ScanResult = { files: [], bindings: [], errors: [] };
  return deriveFreshness({
    registry: makeRegistry([]),
    scan,
    evidence: [],
    policy_mode: "feature",
    generated_at: "2026-07-14T00:00:00Z",
    product_root: "/workspace",
    ...input
  });
}

function errorsFor(status: ReturnType<typeof deriveFreshness>, code: string) {
  return status.integrity_errors.filter((error) => error.code === code);
}

// THE REAL PATH. When a row is renamed in the matrix, its old id is no longer a
// known YAML row, so registry materialization REJECTS the old binding outright
// (REGISTRY_ROW_MISSING) and it never reaches the registry map — it is NOT in
// reconciliation.missing. An earlier version of this suite hand-built a registry
// that still contained the old row, which tested a path production never takes:
// the unit test passed while the real CLI printed no hint at all. This exercises
// the route an actual rename produces.
describe("a rename as the registry actually reports it (REGISTRY_ROW_MISSING)", () => {
  const renamedForReal = {
    rows: [makeRow(NEW_ROW)],
    // The old row is GONE from the matrix, so it is gone from the registry map too.
    registry: makeRegistry([]),
    scan: {
      files: [],
      bindings: [makeBinding(NEW_SLUG, "Sources/Tools/Stage.swift")],
      errors: []
    } as ScanResult,
    // …and surfaces instead as a global registry error naming the old row.
    global_integrity_errors: [
      {
        code: "REGISTRY_ROW_MISSING",
        row_id: OLD_ROW,
        binding_slug: OLD_SLUG,
        message: `row_id ${OLD_ROW} is not a known YAML row`
      }
    ]
  };

  test("REGISTRY_ROW_MISSING names the id it was renamed TO, with a runnable fix", () => {
    const status = run(renamedForReal);
    const [error] = errorsFor(status, "REGISTRY_ROW_MISSING");

    expect(error).toBeDefined();
    expect(error.remediation).toContain(NEW_ROW);
    expect(error.remediation?.toLowerCase()).toContain("renamed");
    expect(error.remediation).toContain("--register-existing");
  });

  test("the UNREGISTERED_BINDING half names the id it was renamed FROM", () => {
    const status = run(renamedForReal);
    const [error] = errorsFor(status, "UNREGISTERED_BINDING");

    expect(error).toBeDefined();
    expect(error.remediation).toContain(OLD_ROW);
    expect(error.remediation?.toLowerCase()).toContain("renamed");
  });

  test("an unrelated orphaned registration is not blamed on a rename", () => {
    const status = run({
      rows: [makeRow("billing.refund_invoice")],
      registry: makeRegistry([]),
      scan: {
        files: [],
        bindings: [makeBinding("billing.refund_invoice#handler", "Sources/Billing.swift")],
        errors: []
      } as ScanResult,
      global_integrity_errors: [
        {
          code: "REGISTRY_ROW_MISSING",
          row_id: OLD_ROW,
          binding_slug: OLD_SLUG,
          message: "gone"
        }
      ]
    });
    const [error] = errorsFor(status, "REGISTRY_ROW_MISSING");

    expect(error).toBeDefined();
    // Still actionable, but it does not invent a rename.
    expect(error.remediation).toBeTruthy();
    expect(error.remediation?.toLowerCase()).not.toContain("renamed to");
  });
});

describe("scan detects a likely rename instead of just reporting wreckage", () => {
  // The rename: the row was renamed in the matrix AND in the source markers, but
  // the binding registry still holds the OLD slug. Registered slug vanished; a
  // near-identical unregistered marker appeared.
  const renamed = {
    rows: [makeRow(NEW_ROW)],
    registry: makeRegistry([[OLD_ROW, OLD_SLUG]]),
    scan: {
      files: [],
      bindings: [makeBinding(NEW_SLUG, "Sources/Tools/Stage.swift")],
      errors: []
    } as ScanResult
  };

  test("UNREGISTERED_BINDING names the row it was probably renamed FROM", () => {
    const status = run(renamed);
    const [error] = errorsFor(status, "UNREGISTERED_BINDING");

    expect(error).toBeDefined();
    expect(error.remediation).toContain(OLD_ROW);
    expect(error.remediation?.toLowerCase()).toContain("renamed");
  });

  test("does not guess when two candidates are equally plausible", () => {
    // Two old rows both vanished and both look like the new id. A wrong rename
    // suggestion is worse than none, so it must stay silent about WHICH.
    const ambiguous = {
      rows: [makeRow(NEW_ROW)],
      registry: makeRegistry([
        ["sidecar.tools.mcp_stagea", "sidecar.tools.mcp_stagea#handler"],
        ["sidecar.tools.mcp_stageb", "sidecar.tools.mcp_stageb#handler"]
      ]),
      scan: {
        files: [],
        bindings: [makeBinding(NEW_SLUG, "Sources/Tools/Stage.swift")],
        errors: []
      } as ScanResult
    };
    const status = run(ambiguous);
    const [error] = errorsFor(status, "UNREGISTERED_BINDING");

    expect(error).toBeDefined();
    // Still actionable (the generic cure), but no rename claim.
    expect(error.remediation).toBeTruthy();
    expect(error.remediation?.toLowerCase()).not.toContain("renamed from");
  });

  test("does not cry rename for an unrelated new marker", () => {
    const unrelated = {
      rows: [makeRow("billing.refund_invoice")],
      registry: makeRegistry([[OLD_ROW, OLD_SLUG]]),
      scan: {
        files: [],
        bindings: [makeBinding("billing.refund_invoice#handler", "Sources/Billing.swift")],
        errors: []
      } as ScanResult
    };
    const status = run(unrelated);
    const [error] = errorsFor(status, "UNREGISTERED_BINDING");

    expect(error).toBeDefined();
    expect(error.remediation?.toLowerCase()).not.toContain("renamed from");
  });
});
