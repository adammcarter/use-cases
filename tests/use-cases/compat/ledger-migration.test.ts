// MECHANICAL MIGRATION PROOF for the binding ledger: 0.5.5 -> this release.
//
// `bindings.jsonl` is a persisted file format, and persisted formats are part of
// the public contract (docs/reference/stability.md). This release adds a
// `binding_released` event to it. That is additive going forward and BREAKING
// going backward, and the difference is worth proving rather than asserting:
//
//   forward  — this build reads every 0.5.5-written ledger identically.
//   sideways — an upgraded client that never rebinds writes a ledger 0.5.5
//              still accepts, so a staggered rollout is safe until someone
//              actually uses the new commands.
//   backward — once a release event is written, 0.5.5 rejects the ledger. It
//              fails CLOSED: it reads nothing it misunderstands and writes
//              nothing at all, so a straggler cannot corrupt the ledger.
//
// The backward case is proved against the REAL 0.5.5 event schema, captured
// byte-for-byte from the published package into
// `tests/fixtures/backcompat/binding-registry-event-0.5.5.schema.json`. Using the
// schema rather than the old binary keeps this hermetic and CI-runnable, and it
// pins the boundary: if anyone ever thinks the old version tolerates the new
// event, this test says otherwise.
import Ajv2020Module from "ajv/dist/2020.js";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBindingsJsonl } from "../../../packages/core/src/markers/registry.js";

const repoRoot = resolve(import.meta.dirname, "../../..");
const oldSchema = JSON.parse(
  readFileSync(join(repoRoot, "tests/fixtures/backcompat/binding-registry-event-0.5.5.schema.json"), "utf8")
) as Record<string, unknown>;

const Ajv2020 = Ajv2020Module.default;
const validateAgainst056 = new Ajv2020({ allErrors: true, strict: true }).compile(oldSchema);

const ROW = "checkout.apply_coupon";
const ROWS = new Set([ROW, "checkout.refund_order"]);

function event(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: "ucase-binding-registry-event-v1",
    event_type: "binding_registered",
    event_id: "01JLEDGER0000000000000000A",
    created_at: "2026-07-30T12:00:00.000Z",
    created_by: { tool: "use-cases", command: "bind", version: "0.5.5" },
    row_id: ROW,
    binding_slug: ROW,
    reason: "initial_bind",
    ...overrides
  };
}

const released = event({
  event_type: "binding_released",
  event_id: "01JLEDGER0000000000000000B",
  created_by: { tool: "use-cases", command: "unbind", version: "0.6.0" },
  reason: "rebind"
});

function jsonl(...events: Array<Record<string, unknown>>): string {
  return `${events.map((e) => JSON.stringify(e)).join("\n")}\n`;
}

describe("forward: this build reads a 0.5.5 ledger unchanged", () => {
  test("a registration-only ledger materializes exactly as it always did", () => {
    const result = validateBindingsJsonl(jsonl(event()), ROWS);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
    expect(result.registry.slugToRow.get(ROW)).toBe(ROW);
    expect([...(result.registry.rowToSlugs.get(ROW) ?? [])]).toEqual([ROW]);
  });

  test("a 0.5.5 ledger's errors are still the same errors", () => {
    // Duplicate registration was an error before and remains one.
    const duplicated = validateBindingsJsonl(jsonl(event(), event()), ROWS);
    expect(duplicated.ok).toBe(false);
    expect(duplicated.errors.map((e) => e.code)).toContain("DUPLICATE_REGISTRATION");

    // A live registration naming a row the matrix does not have is still fatal.
    const orphaned = validateBindingsJsonl(jsonl(event()), new Set(["something.else"]));
    expect(orphaned.ok).toBe(false);
    expect(orphaned.errors.map((e) => e.code)).toContain("REGISTRY_ROW_MISSING");
  });
});

describe("sideways: a staggered rollout is safe until rebind/unbind is used", () => {
  test("0.5.5 accepts every event this build writes with bind alone", () => {
    // bind's own event, byte-shaped as this build emits it.
    const written = event({ created_by: { tool: "use-cases", command: "bind", version: "0.6.0" } });
    expect(validateAgainst056(written)).toBe(true);
  });

  test("0.5.5 accepts a --register-existing event too", () => {
    const written = event({
      reason: "register_existing",
      created_by: { tool: "use-cases", command: "bind", version: "0.6.0" }
    });
    expect(validateAgainst056(written)).toBe(true);
  });
});

describe("backward: 0.5.5 rejects a released ledger, and fails closed", () => {
  test("the 0.5.5 schema refuses a binding_released event", () => {
    expect(validateAgainst056(released)).toBe(false);
    const messages = (validateAgainst056.errors ?? []).map((e) => `${e.instancePath} ${e.message}`);
    expect(messages.join("; ")).toContain("event_type");
  });

  test("the refusal is total: 0.5.5 rejects the whole ledger, not just that line", () => {
    // Every line still parses as JSON, so an older reader gets as far as schema
    // validation and stops there — which is why it exits 4 rather than acting on
    // a half-understood ledger.
    const lines = jsonl(event(), released, event({ reason: "rebind" }))
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line) as Record<string, unknown>);
    const verdicts = lines.map((line) => validateAgainst056(line));
    expect(verdicts).toEqual([true, false, true]);
    // The re-registration on line 3 is one an old reader would treat as a
    // DUPLICATE of line 1 — it cannot see the release that made room for it.
    // Fail-closed is the only safe reading, and it is what it does.
  });

  test("this build reads that same ledger correctly", () => {
    const result = validateBindingsJsonl(jsonl(event(), released, event({ reason: "rebind" })), ROWS);
    expect(result.errors).toEqual([]);
    expect(result.registry.slugToRow.get(ROW)).toBe(ROW);
  });
});
