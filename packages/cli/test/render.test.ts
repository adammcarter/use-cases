// BLOCKER 2 (human framing + exit parity) — the human (non-json) view must NEVER
// present unqualified success (a green header/✓/"fresh") when the command FAILED
// (envelope ok:false), and the render layer must be a pure function of the
// envelope so the process exit code is IDENTICAL in --json and human mode.
//
// These tests drive the REAL renderEnvelope over representative trust envelopes
// (scan FRESH / SUSPECT / no-key VERIFIED_LOCAL, verify pass/fail) and assert the
// human framing MATCHES the envelope ok. Exit-code parity is covered structurally
// (the dispatcher returns one exitCode used for both renders) plus a guard test
// that the same envelope renders the same failure framing regardless of caller.
import { describe, expect, test } from "vitest";
import { renderEnvelope } from "../src/render.js";

// A minimal trust-shaped envelope, matching the fields render.ts/trustRender.ts read.
function scanEnvelope(options: {
  ok: boolean;
  exitCode: number;
  rows: Array<{ row_id: string; status: string; local_status?: string | null }>;
  summary?: Partial<{ fresh: number; suspect: number; unproven: number; unbound: number; invalid: number }>;
}) {
  const summary = { fresh: 0, suspect: 0, unproven: 0, unbound: 0, invalid: 0, ...options.summary };
  return {
    command: "markers.scan",
    ok: options.ok,
    complete: options.ok,
    data: {
      exit_code: options.exitCode,
      ok: options.ok,
      status: { summary, rows: options.rows },
      registry_valid: true,
      evidence_valid: options.ok
    }
  };
}

function verifyEnvelope(options: {
  ok: boolean;
  exitCode: number;
  results: Array<{ row_id: string; status: "pass" | "fail" | "blocked" }>;
}) {
  return {
    command: "markers.verify",
    ok: options.ok,
    complete: options.ok,
    data: {
      exit_code: options.exitCode,
      ok: options.ok,
      command: "verify",
      results: options.results,
      out_path: null,
      errors: []
    }
  };
}

// Does the human text present UNQUALIFIED success? A green light with no failure
// marker. We look for the affirmative signals ("✓"/"fresh"/"passed") NOT paired
// with any failure signal ("✗"/"FAILED"/"failed").
function looksUnqualifiedGreen(text: string): boolean {
  const hasFailureMarker = /✗|FAILED|\bfailed\b/i.test(text);
  const hasSuccessMarker = /✓|\bfresh\b/i.test(text);
  return hasSuccessMarker && !hasFailureMarker;
}

describe("BLOCKER 2 — human trust view never shows green while the command failed", () => {
  test("scan FRESH (ok:true, exit 0): green human view is truthful", () => {
    const env = scanEnvelope({
      ok: true,
      exitCode: 0,
      rows: [{ row_id: "checkout.apply_coupon", status: "FRESH", local_status: "VERIFIED_LOCAL" }],
      summary: { fresh: 1 }
    });
    const human = renderEnvelope(env, false);
    expect(human).toMatch(/✓/);
    // Truthful green is allowed when ok:true.
    expect(looksUnqualifiedGreen(human)).toBe(true);
  });

  test("scan no-key VERIFIED_LOCAL but ok:false/exit 4: human view must SURFACE the failure (no unqualified green)", () => {
    // A keyless VERIFIED_LOCAL row that nonetheless FAILED the command (e.g. a
    // configured key rejected a proof -> exit 4). The per-row glyph is green, but
    // the envelope failed, so the human framing must NOT read as unqualified pass.
    const env = scanEnvelope({
      ok: false,
      exitCode: 4,
      rows: [{ row_id: "checkout.apply_coupon", status: "UNPROVEN", local_status: "VERIFIED_LOCAL" }],
      summary: { unproven: 1 }
    });
    const human = renderEnvelope(env, false);
    expect(looksUnqualifiedGreen(human)).toBe(false);
  });

  test("scan SUSPECT (ok:false, exit 1): human view surfaces the failure", () => {
    const env = scanEnvelope({
      ok: false,
      exitCode: 1,
      rows: [{ row_id: "checkout.apply_coupon", status: "SUSPECT", local_status: null }],
      summary: { suspect: 1 }
    });
    const human = renderEnvelope(env, false);
    expect(looksUnqualifiedGreen(human)).toBe(false);
    expect(human).toMatch(/✗/);
  });

  test("verify all-pass (ok:true): truthful green", () => {
    const env = verifyEnvelope({
      ok: true,
      exitCode: 0,
      results: [{ row_id: "checkout.apply_coupon", status: "pass" }]
    });
    const human = renderEnvelope(env, false);
    expect(human).toMatch(/✓/);
  });

  test("verify with a failing row (ok:false): human view surfaces the failure", () => {
    const env = verifyEnvelope({
      ok: false,
      exitCode: 1,
      results: [{ row_id: "checkout.apply_coupon", status: "fail" }]
    });
    const human = renderEnvelope(env, false);
    expect(looksUnqualifiedGreen(human)).toBe(false);
    expect(human).toMatch(/✗/);
  });
});

describe("recover — concise human view (not the raw status envelope)", () => {
  function recoverEnvelope(options: {
    ok: boolean;
    exitCode: number;
    recovered: boolean;
    proved?: boolean;
    target: string;
    rows: Array<{ row_id: string; status: string; local_status?: string | null }>;
    diagnostics?: Array<{ code: string; severity?: string; message: string }>;
  }) {
    return {
      command: "markers.recover",
      ok: options.ok,
      complete: options.ok,
      data: {
        exit_code: options.exitCode,
        recovered: options.recovered,
        proved: options.proved ?? false,
        target: options.target,
        results_path: "/tmp/x/.use-cases/verification-results.jsonl",
        // recover mirrors scan's status shape; the raw envelope also carries
        // row_hash / span_sha256s / verification_context_hash under status.rows —
        // exactly the noisy tree the concise view must NOT dump.
        status: {
          schema: "ucase-freshness-status-v1",
          generated_at: "2026-07-04T00:00:00Z",
          verification_context_hash: "ctx-deadbeef",
          summary: { fresh: 0, suspect: 0, unproven: 0, unbound: 0, invalid: 0 },
          rows: options.rows.map((r) => ({
            ...r,
            row_hash: "rowhash-deadbeef",
            span_sha256s: ["span-deadbeef"],
            verification_context_hash: "ctx-deadbeef"
          }))
        }
      },
      ...(options.diagnostics ? { diagnostics: options.diagnostics } : {})
    };
  }

  test("a drifted-then-recovered row prints a SHORT success summary (recovered -> green), not the nested envelope", () => {
    const env = recoverEnvelope({
      ok: true,
      exitCode: 0,
      recovered: true,
      target: "checkout.apply_coupon",
      rows: [{ row_id: "checkout.apply_coupon", status: "UNPROVEN", local_status: "VERIFIED_LOCAL" }]
    });
    const human = renderEnvelope(env, false);
    // Reads as success/recovered.
    expect(human).toMatch(/recovered/i);
    expect(human).toMatch(/checkout\.apply_coupon/);
    // Green state is surfaced.
    expect(human).toMatch(/VERIFIED_LOCAL|green/i);
    // The raw hash envelope is NOT dumped.
    expect(human).not.toMatch(/row_hash/);
    expect(human).not.toMatch(/span_sha256s/);
    expect(human).not.toMatch(/verification_context_hash/);
    // And it must NOT headline "run uc prove" when the keyless light is already green.
    expect(human).not.toMatch(/uc prove/);
    // Nor headline UNPROVEN / required_action.
    expect(human).not.toMatch(/required_action/);
  });

  test("a row that could NOT be recovered shows a next action", () => {
    const env = recoverEnvelope({
      ok: false,
      exitCode: 1,
      recovered: false,
      target: "checkout.apply_coupon",
      rows: [{ row_id: "checkout.apply_coupon", status: "SUSPECT", local_status: "STALE_LOCAL" }],
      diagnostics: [{ code: "recover.not_green", severity: "error", message: "recover re-verified checkout.apply_coupon but it did not reach VERIFIED_LOCAL." }]
    });
    const human = renderEnvelope(env, false);
    // Surfaces failure (not an unqualified green).
    expect(looksUnqualifiedGreen(human)).toBe(false);
    // Still concise — no raw hash tree.
    expect(human).not.toMatch(/span_sha256s/);
    // Gives the user a next action.
    expect(human).toMatch(/→|next|verify|scan/i);
  });

  test("recover that fails BEFORE it can scan (no status rows) still tells the user WHY and what to do", () => {
    // The verifier-failed path returns before recover can produce a status
    // block, so `status.rows` is empty. The only source of the reason + the next
    // step is the envelope diagnostic. A concise view that dropped it left the
    // reader with a bare "could NOT recover" headline and a blank line — the
    // 0.2.0 regression this test locks shut.
    const env = {
      command: "markers.recover",
      ok: false,
      complete: false,
      data: {
        exit_code: 1,
        recovered: false,
        proved: false,
        target: "checkout.apply_coupon",
        results_path: "/tmp/x/.use-cases/verification-results.jsonl",
        status: { schema: "ucase-freshness-status-v1", rows: [] }
      },
      diagnostics: [
        {
          code: "recover.verification_failed",
          severity: "error",
          message:
            "recover could not restore checkout.apply_coupon to green: the verifier failed. Fix the code or the test, then re-run `uc recover`. Inspect the failure with `uc verify --row checkout.apply_coupon`."
        }
      ]
    };
    const human = renderEnvelope(env, false);
    // Reads as failure, never as unqualified green.
    expect(looksUnqualifiedGreen(human)).toBe(false);
    expect(human).toMatch(/could NOT recover|FAILED/i);
    // The WHY (verifier failed) and the next step (re-run / uc verify) survive
    // into the concise human view — not just the --json envelope.
    expect(human).toMatch(/verifier failed/i);
    expect(human).toMatch(/uc verify --row checkout\.apply_coupon/);
    // Still concise — no raw hash tree leaked in.
    expect(human).not.toMatch(/span_sha256s/);
  });
});

describe("scan count vocabulary — keyless VERIFIED_LOCAL is not conflated with signed FRESH", () => {
  test("a keyless VERIFIED_LOCAL row is NOT counted as 'fresh' in the header", () => {
    const env = scanEnvelope({
      ok: true,
      exitCode: 0,
      rows: [{ row_id: "checkout.apply_coupon", status: "UNPROVEN", local_status: "VERIFIED_LOCAL" }],
      summary: { unproven: 1 }
    });
    const human = renderEnvelope(env, false);
    // The header must not call a keyless local pass "fresh" (the signed tier word).
    expect(human).not.toMatch(/1 fresh/);
    // It is still reported as green (verified-local), just under an honest word.
    expect(human).toMatch(/verified-local|1 green/i);
  });

  test("a signed FRESH row is still counted under 'fresh'", () => {
    const env = scanEnvelope({
      ok: true,
      exitCode: 0,
      rows: [{ row_id: "checkout.apply_coupon", status: "FRESH", local_status: "VERIFIED_LOCAL" }],
      summary: { fresh: 1 }
    });
    const human = renderEnvelope(env, false);
    expect(human).toMatch(/1 fresh/);
  });
});

describe("GATE HONESTY — a passing gate must warn about ungated drift", () => {
  function gateScanEnvelope(gate: {
    blocked: boolean;
    required_bar: string;
    offending_rows?: Array<{ row_id: string }>;
    ungated_below_bar?: Array<{ row_id: string; status: string; local_status?: string | null }>;
  }, rows: Array<{ row_id: string; status: string; local_status?: string | null; required_for_release?: boolean }>, summary: Partial<{ fresh: number; suspect: number; unproven: number; unbound: number; invalid: number }>) {
    return {
      command: "markers.scan",
      ok: true,
      complete: true,
      data: {
        exit_code: 0,
        ok: true,
        status: { summary: { fresh: 0, suspect: 0, unproven: 0, unbound: 0, invalid: 0, ...summary }, rows },
        registry_valid: true,
        evidence_valid: true,
        gate: { policy_mode: "release", ...gate }
      }
    };
  }

  test("gate passed states HOW MANY required behaviours met the bar", () => {
    const env = gateScanEnvelope(
      { blocked: false, required_bar: "FRESH", offending_rows: [], ungated_below_bar: [] },
      [
        { row_id: "req.a", status: "FRESH", local_status: "VERIFIED_LOCAL", required_for_release: true },
        { row_id: "req.b", status: "FRESH", local_status: "VERIFIED_LOCAL", required_for_release: true }
      ],
      { fresh: 2 }
    );
    const human = renderEnvelope(env, false);
    expect(human).toMatch(/gate passed/);
    // Names the count of required behaviours evaluated against the bar.
    expect(human).toMatch(/2 required behaviours? meet FRESH/i);
  });

  test("a passing gate WARNS about a non-required SUSPECT row that is not gated", () => {
    const env = gateScanEnvelope(
      {
        blocked: false,
        required_bar: "FRESH",
        offending_rows: [],
        ungated_below_bar: [{ row_id: "drifted.row", status: "SUSPECT", local_status: "STALE_LOCAL" }]
      },
      [
        { row_id: "req.a", status: "FRESH", local_status: "VERIFIED_LOCAL", required_for_release: true },
        { row_id: "drifted.row", status: "SUSPECT", local_status: "STALE_LOCAL" }
      ],
      { fresh: 1, suspect: 1 }
    );
    const human = renderEnvelope(env, false);
    // The pass line still shows.
    expect(human).toMatch(/gate passed/);
    // But a warning surfaces the ungated drift + the exact knob to enforce it.
    expect(human).toMatch(/⚠/);
    expect(human).toMatch(/not gated|NOT gated/);
    expect(human).toMatch(/drifted\.row/);
    expect(human).toMatch(/required_for_release/);
  });
});

describe("BLOCKER 2 — render is a pure function of the envelope (exit-code parity precondition)", () => {
  // The dispatcher returns ONE exitCode and renders the SAME envelope in both
  // modes; parity holds iff the render layer never alters control flow by mode.
  // Here we assert the JSON bytes stay canonical and the human view reflects the
  // SAME ok as the json envelope for both a passing and a failing case.
  test("json bytes are byte-identical JSON.stringify + newline", () => {
    const env = scanEnvelope({ ok: true, exitCode: 0, rows: [], summary: {} });
    expect(renderEnvelope(env, true)).toBe(`${JSON.stringify(env)}\n`);
  });

  test("a failing envelope renders ok:false in json AND a non-green human view (same truth)", () => {
    const env = scanEnvelope({
      ok: false,
      exitCode: 4,
      rows: [{ row_id: "r", status: "UNPROVEN", local_status: "VERIFIED_LOCAL" }],
      summary: { unproven: 1 }
    });
    const json = JSON.parse(renderEnvelope(env, true));
    expect(json.ok).toBe(false);
    const human = renderEnvelope(env, false);
    expect(looksUnqualifiedGreen(human)).toBe(false);
  });
});
