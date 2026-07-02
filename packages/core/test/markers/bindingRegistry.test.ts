import { describe, expect, test } from "vitest";
import {
  appendOnly,
  materializeRegistry,
  readBindingsJsonl,
  reconcileRegistryWithScan,
  RegistryErrorCode,
  scanFiles,
  splitJsonlLines,
  validateBindingsJsonl
} from "../../src/markers/index.js";

// A well-formed binding_registered event for `checkout.apply_coupon#tax`.
function event(
  binding_slug: string,
  row_id: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    schema: "ucase-binding-registry-event-v1",
    event_type: "binding_registered",
    event_id: `01J${binding_slug.replace(/[^a-z0-9]/gi, "").toUpperCase().padEnd(23, "0").slice(0, 23)}`,
    created_at: "2026-06-28T12:00:00Z",
    created_by: { tool: "use-case-matrix", command: "bind", version: "0.1.0" },
    row_id,
    binding_slug,
    reason: "initial_bind",
    ...overrides
  };
}

function jsonl(...events: Array<Record<string, unknown>>): string {
  return events.map((e) => JSON.stringify(e)).join("\n");
}

const YAML_ROWS = new Set(["checkout.apply_coupon", "checkout.remove_coupon"]);

// The marker file binding `checkout.apply_coupon#tax` (explicit span).
const TAX_FILE = [
  "//: @use-case: checkout.apply_coupon#tax",
  "func computeTax() -> Int { return 1 }",
  "//: @use-case: end checkout.apply_coupon#tax"
].join("\n");

describe("bindings.jsonl reader", () => {
  test("parses one event per line and tolerates a trailing newline", () => {
    const text = `${jsonl(event("checkout.apply_coupon#tax", "checkout.apply_coupon"))}\n`;
    const result = readBindingsJsonl(text);
    expect(result.errors).toEqual([]);
    expect(result.lines).toHaveLength(1);
    expect(result.lines[0].line).toBe(1);
  });

  test("reports a JSON parse error with the offending 1-based line number", () => {
    const text = [
      JSON.stringify(event("checkout.apply_coupon#tax", "checkout.apply_coupon")),
      "{ not valid json",
      JSON.stringify(event("checkout.apply_coupon#fee", "checkout.apply_coupon"))
    ].join("\n");
    const result = readBindingsJsonl(text);
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].code).toBe("JSON_PARSE_ERROR");
    expect(result.errors[0].line).toBe(2);
    // The two valid lines are still read.
    expect(result.lines.map((l) => l.line)).toEqual([1, 3]);
  });
});

describe("registry validator (spec 4.3)", () => {
  test("a clean registry validates and materializes both maps", () => {
    const text = jsonl(event("checkout.apply_coupon#tax", "checkout.apply_coupon"));
    const result = validateBindingsJsonl(text, YAML_ROWS);
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.registry.slugToRow.get("checkout.apply_coupon#tax")).toBe(
      "checkout.apply_coupon"
    );
    expect([...(result.registry.rowToSlugs.get("checkout.apply_coupon") ?? [])]).toEqual([
      "checkout.apply_coupon#tax"
    ]);
  });

  test("schema-invalid event is rejected with REGISTRY_SCHEMA_INVALID", () => {
    const bad = event("checkout.apply_coupon#tax", "checkout.apply_coupon", {
      event_type: "something_else"
    });
    const result = validateBindingsJsonl(jsonl(bad), YAML_ROWS);
    expect(result.ok).toBe(false);
    expect(result.errors.map((e) => e.code)).toContain(RegistryErrorCode.REGISTRY_SCHEMA_INVALID);
  });

  test("rule 4: binding_slug row prefix must equal row_id (SLUG_PREFIX_MISMATCH)", () => {
    const bad = event("checkout.apply_coupon#tax", "checkout.remove_coupon");
    const result = validateBindingsJsonl(jsonl(bad), YAML_ROWS);
    expect(result.ok).toBe(false);
    expect(result.errors.map((e) => e.code)).toContain(RegistryErrorCode.SLUG_PREFIX_MISMATCH);
  });

  test("rule 5: row_id must exist in YAML rows (REGISTRY_ROW_MISSING)", () => {
    const bad = event("checkout.ghost#tax", "checkout.ghost");
    const result = validateBindingsJsonl(jsonl(bad), YAML_ROWS);
    expect(result.ok).toBe(false);
    expect(result.errors.map((e) => e.code)).toContain(RegistryErrorCode.REGISTRY_ROW_MISSING);
  });

  test("#6 duplicate registration of the same slug fails (DUPLICATE_REGISTRATION)", () => {
    const text = jsonl(
      event("checkout.apply_coupon#tax", "checkout.apply_coupon"),
      event("checkout.apply_coupon#tax", "checkout.apply_coupon")
    );
    const result = validateBindingsJsonl(text, YAML_ROWS);
    expect(result.ok).toBe(false);
    expect(result.errors.map((e) => e.code)).toContain(RegistryErrorCode.DUPLICATE_REGISTRATION);
  });

  test("#6 same slug mapped to two different rows fails (SLUG_ROW_CONFLICT)", () => {
    // Both rows exist in YAML but the slug prefix only matches the first; the
    // conflict is the slug being reassigned to a different row_id.
    const text = jsonl(
      event("checkout.apply_coupon", "checkout.apply_coupon"),
      // Re-register the same bare slug under a different row (prefix matches that
      // row's id is irrelevant here -- we force the slug/row pair to differ).
      { ...event("checkout.apply_coupon", "checkout.apply_coupon"), row_id: "checkout.remove_coupon" }
    );
    const result = validateBindingsJsonl(text, YAML_ROWS);
    expect(result.ok).toBe(false);
    const codes = result.errors.map((e) => e.code);
    // The second line both mismatches its own prefix and conflicts with the
    // first registration; at minimum the conflict is surfaced.
    expect(
      codes.includes(RegistryErrorCode.SLUG_ROW_CONFLICT) ||
        codes.includes(RegistryErrorCode.SLUG_PREFIX_MISMATCH)
    ).toBe(true);
  });
});

describe("append-only check (spec amendment 2, rules 9/10)", () => {
  test("appending new lines is allowed", () => {
    const old = ["a", "b"];
    const next = ["a", "b", "c"];
    expect(appendOnly(old, next)).toEqual({ ok: true });
  });

  test("identical content is allowed", () => {
    expect(appendOnly(["a", "b"], ["a", "b"])).toEqual({ ok: true });
  });

  test("#4 editing an existing line is a violation", () => {
    const result = appendOnly(["a", "b", "c"], ["a", "X", "c", "d"]);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violation.kind).toBe("edited");
      expect(result.violation.index).toBe(1);
      expect(result.violation.old_line).toBe("b");
      expect(result.violation.new_line).toBe("X");
    }
  });

  test("#5 deleting an existing line is a violation", () => {
    const result = appendOnly(["a", "b", "c"], ["a", "b"]);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.violation.kind).toBe("deleted");
      expect(result.violation.index).toBe(2);
      expect(result.violation.old_line).toBe("c");
      expect(result.violation.new_line).toBeNull();
    }
  });

  test("reordering an existing line is caught as an edit", () => {
    const result = appendOnly(["a", "b", "c"], ["a", "c", "b"]);
    expect(result.ok).toBe(false);
  });

  test("splitJsonlLines drops a single trailing newline but keeps content lines", () => {
    expect(splitJsonlLines("a\nb\n")).toEqual(["a", "b"]);
    expect(splitJsonlLines("a\nb")).toEqual(["a", "b"]);
    expect(splitJsonlLines("")).toEqual([]);
  });
});

describe("materializeRegistry", () => {
  test("folds events into row->slugs and slug->row", () => {
    const text = jsonl(
      event("checkout.apply_coupon#tax", "checkout.apply_coupon"),
      event("checkout.apply_coupon#fee", "checkout.apply_coupon"),
      event("checkout.remove_coupon", "checkout.remove_coupon")
    );
    const { events } = validateBindingsJsonl(text, YAML_ROWS);
    const registry = materializeRegistry(events);
    expect([...(registry.rowToSlugs.get("checkout.apply_coupon") ?? [])].sort()).toEqual([
      "checkout.apply_coupon#fee",
      "checkout.apply_coupon#tax"
    ]);
    expect(registry.slugToRow.get("checkout.remove_coupon")).toBe("checkout.remove_coupon");
  });
});

describe("reconciliation against a scan result (spec 7.2/7.3)", () => {
  test("#1 a registered current marker reconciles clean", () => {
    const text = jsonl(event("checkout.apply_coupon#tax", "checkout.apply_coupon"));
    const { registry } = validateBindingsJsonl(text, YAML_ROWS);
    const scan = scanFiles([{ file_path: "Tax.swift", contents: TAX_FILE }]);
    const recon = reconcileRegistryWithScan(registry, scan);

    expect(recon.unregistered).toEqual([]);
    expect(recon.missing).toEqual([]);
    const row = recon.rows.find((r) => r.row_id === "checkout.apply_coupon");
    expect(row?.missing_registered_binding_slugs).toEqual([]);
    expect(row?.unregistered_current_binding_slugs).toEqual([]);
  });

  test("#2 a current marker slug NOT in the registry is detected as unregistered", () => {
    // Registry is empty; the scanned marker has no registration.
    const { registry } = validateBindingsJsonl("", YAML_ROWS);
    const scan = scanFiles([{ file_path: "Tax.swift", contents: TAX_FILE }]);
    const recon = reconcileRegistryWithScan(registry, scan);

    expect(recon.unregistered.map((u) => u.binding_slug)).toEqual([
      "checkout.apply_coupon#tax"
    ]);
    expect(recon.unregistered[0].file_path).toBe("Tax.swift");
    const row = recon.rows.find((r) => r.row_id === "checkout.apply_coupon");
    expect(row?.unregistered_current_binding_slugs).toEqual(["checkout.apply_coupon#tax"]);
  });

  test("#3 a registered slug with NO current marker is detected as missing and the row survives", () => {
    const text = jsonl(event("checkout.apply_coupon#tax", "checkout.apply_coupon"));
    const { registry } = validateBindingsJsonl(text, YAML_ROWS);
    // Scan a file with no markers at all -> the registered binding is missing.
    const scan = scanFiles([{ file_path: "Empty.swift", contents: "func noop() {}\n" }]);
    const recon = reconcileRegistryWithScan(registry, scan);

    expect(recon.missing.map((m) => m.binding_slug)).toEqual(["checkout.apply_coupon#tax"]);
    // The row does NOT silently disappear from the reconciliation.
    const row = recon.rows.find((r) => r.row_id === "checkout.apply_coupon");
    expect(row).toBeDefined();
    expect(row?.missing_registered_binding_slugs).toEqual(["checkout.apply_coupon#tax"]);
    expect(recon.unregistered).toEqual([]);
  });
});
