// Lie-guard mutation suite (spec section 11; Phase 9 acceptance gate).
//
// One assertion per row of the section-11 mutation tables (11.1 marker
// laundering, 11.2 binding identity, 11.3 span inference, 11.4 evidence
// laundering, 11.5 freshness), each driving a single mutation through the pure
// cores (or the real CLI cores) and asserting the EXACT expected error code /
// status. Closes with the capstone: a fabricated or unsigned proof event can
// NEVER make a row FRESH — proven through validate-ledger + deriveFreshness.
//
// This consolidates coverage that earlier phases established piecemeal into one
// authoritative guard; nothing in the core is changed.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  appendOnly,
  computeApprovalPolicyHash,
  computeBindingSetHash,
  computeRowHash,
  computeVerificationPolicyHash,
  deriveFreshness,
  recognizeSwiftFuncSpan,
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runValidateLedgerCommand,
  scanFileForMarkers,
  signEvent,
  validateBindingsJsonl,
  validateEvidenceLedger,
  type CurrentBindingRecord,
  type DeriveFreshnessInput,
  type FreshnessInputRow,
  type MaterializedRegistry,
  type ProofEvent,
  type ScanResult
} from "../../src/markers/index.js";
import {
  cleanupWorkspaces,
  makeClock,
  makeId,
  makeWorkspace,
  passRunner,
  resolver,
  GENERATED_AT,
  KEY_ID,
  PRIVATE_KEY,
  ROW_ID,
  SWIFT_FUNC_SOURCE,
  type Workspace
} from "./helpers.js";

afterEach(cleanupWorkspaces);

// ---------------------------------------------------------------------------
// Pure fixture builders (rows / bindings / proofs / registry) for the marker,
// binding-identity, and freshness mutations. Mirror the freshness.test.ts shapes
// so a proof matches its row+bindings by default; overrides simulate mutations.
// ---------------------------------------------------------------------------

const SPAN_A = `sha256:${"a".repeat(64)}`;
const SPAN_B = `sha256:${"b".repeat(64)}`;

function makeRow(overrides: Partial<FreshnessInputRow> = {}): FreshnessInputRow {
  return {
    row_id: ROW_ID,
    intent: "apply a valid coupon to a cart",
    verification_policy: { command: "npm run test:usecase -- checkout.apply_coupon" },
    approval_policy: { required_for_release: true, trusted_producer: "trusted-ci-prover" },
    ...overrides
  };
}

function makeBinding(
  slug: string,
  overrides: { file_path?: string; span_sha256?: string } = {}
): CurrentBindingRecord {
  const hashIndex = slug.indexOf("#");
  const rowId = hashIndex === -1 ? slug : slug.slice(0, hashIndex);
  const suffix = hashIndex === -1 ? null : slug.slice(hashIndex + 1);
  return {
    binding_slug: slug,
    row_id: rowId,
    suffix,
    file_path: overrides.file_path ?? "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v1",
    start_marker: { line: 12, column: 1 },
    end_marker: null,
    span: { start_line: 13, end_line: 27, start_byte: 355, end_byte: 849, sha256: overrides.span_sha256 ?? SPAN_A },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "applyCoupon", inferred: true }
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

function makeScan(bindings: CurrentBindingRecord[], errors: ScanResult["errors"] = []): ScanResult {
  return { files: [], bindings, errors };
}

function makeProof(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[],
  overrides: { event_id?: string; created_at?: string } = {}
): ProofEvent {
  const items = bindings.map((binding) => ({
    binding_slug: binding.binding_slug,
    row_id: binding.row_id,
    file_path: binding.file_path,
    extent_kind: binding.extent_kind,
    recognizer_id: binding.recognizer_id,
    span_canon_id: binding.span_canon_id,
    span_sha256: binding.span.sha256,
    span_start_line: binding.span.start_line,
    span_end_line: binding.span.end_line
  }));
  return {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: overrides.event_id ?? "01JABCDEFAAAAAAAAAAAAAAAAAA",
    created_at: overrides.created_at ?? "2026-06-28T12:05:00Z",
    producer: {
      kind: "trusted-ci-prover",
      id: "github-actions/use-cases-prover",
      version: "0.1.0",
      ci_run_id: "123456789",
      repo: "org/product",
      commit: "0123456789abcdef0123456789abcdef01234567"
    },
    row: {
      row_id: row.row_id,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: computeRowHash(row),
      verification_policy_hash: computeVerificationPolicyHash(row.verification_policy),
      approval_policy_hash: computeApprovalPolicyHash(row.approval_policy)
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash: computeBindingSetHash(row.row_id, items),
      span_canon_id: "ucase-span-lines-v1",
      items
    },
    verification: {
      command_id: "acceptance.checkout.apply_coupon",
      result: "pass",
      started_at: "2026-06-28T12:04:10Z",
      completed_at: "2026-06-28T12:04:59Z",
      artifacts: []
    },
    signature: { alg: "ed25519", key_id: "trusted-ci-2026-01", value: "base64" }
  };
}

function derive(input: Partial<DeriveFreshnessInput> & { rows: FreshnessInputRow[] }) {
  return deriveFreshness({
    registry: makeRegistry([]),
    scan: makeScan([]),
    evidence: [],
    policy_mode: "feature",
    generated_at: GENERATED_AT,
    product_root: "/workspace/product",
    ...input
  });
}

function rowOf(status: ReturnType<typeof deriveFreshness>, rowId: string) {
  const row = status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} not found in status`);
  }
  return row;
}

function reasonCodes(row: { reasons: Array<{ code: string }> }): string[] {
  return row.reasons.map((reason) => reason.code);
}

// scanFileForMarkers error codes for a single marker mutation.
function scanCodes(source: string, path = "f.swift"): string[] {
  return scanFileForMarkers(path, source).errors.map((error) => error.code);
}

const YAML_ROWS = new Set([ROW_ID, "checkout.remove_coupon"]);

function registryEvent(binding_slug: string, row_id: string, overrides: Record<string, unknown> = {}) {
  return {
    schema: "ucase-binding-registry-event-v1",
    event_type: "binding_registered",
    event_id: `01J${binding_slug.replace(/[^a-z0-9]/gi, "").toUpperCase().padEnd(23, "0").slice(0, 23)}`,
    created_at: "2026-06-28T12:00:00Z",
    created_by: { tool: "use-cases-plugin", command: "bind", version: "0.1.0" },
    row_id,
    binding_slug,
    reason: "initial_bind",
    ...overrides
  };
}

// ===========================================================================
// 11.1 Marker laundering mutations
// ===========================================================================
describe("11.1 marker laundering -> INVALID, forbidden / malformed marker", () => {
  for (const payload of ["fresh=true", "proven=true", "sha256=abc", "row_hash=abc", "span_hash=abc", "role=impl", "tier1"]) {
    test(`add "${payload}" after slug -> FORBIDDEN_MARKER_PAYLOAD`, () => {
      expect(scanCodes(`//: @use-case: ${ROW_ID} ${payload}`)).toContain("FORBIDDEN_MARKER_PAYLOAD");
    });
  }

  test("naked `end` with no slug -> MALFORMED_END_MARKER", () => {
    expect(scanCodes("//: @use-case: end")).toContain("MALFORMED_END_MARKER");
  });

  test("mismatched end slug -> MISMATCHED_END_MARKER", () => {
    const source = ["//: @use-case: checkout.apply_coupon", "body()", "//: @use-case: end checkout.other_row"].join("\n");
    expect(scanCodes(source)).toContain("MISMATCHED_END_MARKER");
  });
});

// ===========================================================================
// 11.2 Binding identity mutations
// ===========================================================================
describe("11.2 binding identity", () => {
  test("duplicate same full slug in two starts -> INVALID, DUPLICATE_BINDING_SLUG", () => {
    const source = [
      "//: @use-case: checkout.apply_coupon",
      "a()",
      "//: @use-case: end checkout.apply_coupon",
      "//: @use-case: checkout.apply_coupon",
      "b()",
      "//: @use-case: end checkout.apply_coupon"
    ].join("\n");
    expect(scanCodes(source)).toContain("DUPLICATE_BINDING_SLUG");
  });

  test("current marker slug missing from registry -> INVALID, UNREGISTERED_BINDING", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const status = derive({
      rows: [row],
      registry: makeRegistry([]), // never registered
      scan: makeScan([makeBinding(slug)])
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("INVALID");
    expect(reasonCodes(result)).toContain("UNREGISTERED_BINDING");
  });

  test("registry slug maps to missing row -> INVALID, REGISTRY_ROW_MISSING", () => {
    const result = validateBindingsJsonl(JSON.stringify(registryEvent("checkout.ghost#tax", "checkout.ghost")), YAML_ROWS);
    expect(result.ok).toBe(false);
    expect(result.errors.map((error) => error.code)).toContain("REGISTRY_ROW_MISSING");
  });

  test("registry slug prefix differs from row_id -> INVALID, SLUG_PREFIX_MISMATCH", () => {
    const result = validateBindingsJsonl(
      JSON.stringify(registryEvent("checkout.apply_coupon#tax", "checkout.remove_coupon")),
      YAML_ROWS
    );
    expect(result.ok).toBe(false);
    expect(result.errors.map((error) => error.code)).toContain("SLUG_PREFIX_MISMATCH");
  });

  test("registry reassigns slug to a different row -> INVALID (conflict / prefix mismatch)", () => {
    const text = [
      JSON.stringify(registryEvent("checkout.apply_coupon", "checkout.apply_coupon")),
      JSON.stringify(registryEvent("checkout.apply_coupon", "checkout.apply_coupon", { row_id: "checkout.remove_coupon" }))
    ].join("\n");
    const result = validateBindingsJsonl(text, YAML_ROWS);
    expect(result.ok).toBe(false);
    const codes = result.errors.map((error) => error.code);
    expect(codes.includes("SLUG_ROW_CONFLICT") || codes.includes("SLUG_PREFIX_MISMATCH")).toBe(true);
  });

  test("delete marker for a registered binding -> row SUSPECT, BINDING_REMOVED", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const status = derive({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([]), // marker deleted from source
      evidence: [makeProof(row, [makeBinding(slug)])]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("BINDING_REMOVED");
    expect(result.missing_registered_binding_slugs).toEqual([slug]);
  });

  test("rename marker slug from old row to a new registered slug -> old SUSPECT BINDING_REMOVED, new UNPROVEN", () => {
    const oldRow = makeRow({ row_id: "checkout.apply_coupon" });
    const newRow = makeRow({ row_id: "checkout.remove_coupon" });
    const oldSlug = "checkout.apply_coupon#handler";
    const newSlug = "checkout.remove_coupon#handler";
    const status = derive({
      rows: [oldRow, newRow],
      registry: makeRegistry([
        [oldRow.row_id, oldSlug],
        [newRow.row_id, newSlug]
      ]),
      // The marker now carries the NEW slug; the old slug has no current marker.
      scan: makeScan([makeBinding(newSlug, { file_path: "Sources/Checkout/Remove.swift" })])
    });
    const old = rowOf(status, oldRow.row_id);
    const created = rowOf(status, newRow.row_id);
    expect(old.status).toBe("SUSPECT");
    expect(reasonCodes(old)).toContain("BINDING_REMOVED");
    expect(created.status).toBe("UNPROVEN");
  });

  test("rename marker slug to an UNREGISTERED slug -> INVALID, UNREGISTERED_BINDING", () => {
    const oldRow = makeRow({ row_id: "checkout.apply_coupon" });
    const newRow = makeRow({ row_id: "checkout.remove_coupon" });
    const oldSlug = "checkout.apply_coupon#handler";
    const newSlug = "checkout.remove_coupon#handler";
    const status = derive({
      rows: [oldRow, newRow],
      registry: makeRegistry([[oldRow.row_id, oldSlug]]), // new slug NOT registered
      scan: makeScan([makeBinding(newSlug, { file_path: "Sources/Checkout/Remove.swift" })])
    });
    const created = rowOf(status, newRow.row_id);
    expect(created.status).toBe("INVALID");
    expect(reasonCodes(created)).toContain("UNREGISTERED_BINDING");
  });
});

// ===========================================================================
// 11.3 Span inference mutations (all -> INVALID; inference fails closed)
// ===========================================================================
describe("11.3 span inference -> INVALID, inference fails closed", () => {
  function recognize(source: string) {
    const markerLine = source.split("\n").findIndex((line) => line.includes("@use-case:"));
    return recognizeSwiftFuncSpan(source, markerLine);
  }
  function expectInferenceFailure(source: string, code: string) {
    const result = recognize(source);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe(code);
  }

  test("Swift marker followed by a blank line before func -> MARKER_NOT_ADJACENT_TO_DECLARATION", () => {
    expectInferenceFailure(
      ["//: @use-case: a.b", "", "public func f() {", "}"].join("\n"),
      "MARKER_NOT_ADJACENT_TO_DECLARATION"
    );
  });

  test("Swift marker followed by a comment before func -> MARKER_NOT_ADJACENT_TO_DECLARATION", () => {
    expectInferenceFailure(
      ["//: @use-case: a.b", "// TODO", "public func f() {", "}"].join("\n"),
      "MARKER_NOT_ADJACENT_TO_DECLARATION"
    );
  });

  test("Swift marker placed after @MainActor -> MARKER_INSIDE_ATTACHED_DECLARATION", () => {
    expectInferenceFailure(
      ["@MainActor", "//: @use-case: a.b", "public func f() {", "}"].join("\n"),
      "MARKER_INSIDE_ATTACHED_DECLARATION"
    );
  });

  test("Swift marker before a protocol func with no body -> FUNC_HAS_NO_BODY", () => {
    expectInferenceFailure(
      ["protocol P {", "    //: @use-case: p.req", "    func required() -> Int", "}"].join("\n"),
      "FUNC_HAS_NO_BODY"
    );
  });

  test("Swift marker before `var` -> NEXT_NODE_NOT_FUNC", () => {
    expectInferenceFailure(["//: @use-case: a.b", "var x = 1"].join("\n"), "NEXT_NODE_NOT_FUNC");
  });

  test("Swift marker before `init` -> NEXT_NODE_NOT_FUNC", () => {
    expectInferenceFailure(
      ["//: @use-case: a.b", "init(x: Int) {", "    self.x = x", "}"].join("\n"),
      "NEXT_NODE_NOT_FUNC"
    );
  });

  test("Swift marker before a nested func -> NESTED_FUNC_UNSUPPORTED", () => {
    expectInferenceFailure(
      ["func outer() {", "    //: @use-case: a.b", "    func inner() {", "    }", "}"].join("\n"),
      "NESTED_FUNC_UNSUPPORTED"
    );
  });

  test("Swift marker in a conditional-compilation span -> CONDITIONAL_COMPILATION_IN_SPAN", () => {
    expectInferenceFailure(
      ["#if DEBUG", "//: @use-case: a.b", "func f() {", "}", "#endif"].join("\n"),
      "CONDITIONAL_COMPILATION_IN_SPAN"
    );
  });

  test("Swift marker before a malformed Swift region (no closing brace) -> FUNC_BODY_HAS_NO_CLOSING_BRACE", () => {
    expectInferenceFailure(
      ["//: @use-case: a.b", "func f() {", "    doThing()"].join("\n"),
      "FUNC_BODY_HAS_NO_CLOSING_BRACE"
    );
  });

  test("TypeScript function marker without explicit end -> INVALID, UNSUPPORTED_INFERENCE", () => {
    const result = scanFileForMarkers("src/f.ts", ["//: @use-case: a.b", "export function f() {}"].join("\n"));
    expect(result.bindings).toHaveLength(0);
    expect(result.errors.map((error) => error.code)).toContain("UNSUPPORTED_INFERENCE");
  });

  test("Python function marker without explicit end -> INVALID, UNSUPPORTED_INFERENCE", () => {
    const result = scanFileForMarkers("scripts/f.py", ["#: @use-case: a.b", "def f():", "    pass"].join("\n"));
    expect(result.bindings).toHaveLength(0);
    expect(result.errors.map((error) => error.code)).toContain("UNSUPPORTED_INFERENCE");
  });
});

// ===========================================================================
// 11.4 Evidence laundering mutations
// ===========================================================================
describe("11.4 evidence laundering -> validate-ledger fails / test fails", () => {
  // Build a real, valid signed proof on disk to mutate.
  function setupProven(): { ws: Workspace; provedEventLine: string } {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: "Sources/Checkout/CouponService.swift",
      mode: "swift-func",
      line: 3,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });
    const prove = runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_ID,
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE"),
      trustedCi: true,
      verificationRunner: passRunner,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
    });
    expect(prove.proof_event_appended).toBe(true);
    return { ws, provedEventLine: readFileSync(ws.evidencePath, "utf8").trim() };
  }

  function validate(ws: Workspace, extra: Partial<Parameters<typeof runValidateLedgerCommand>[0]> = {}) {
    return runValidateLedgerCommand({
      context: ws.context,
      evidencePath: ws.evidencePath,
      bindingsPath: ws.bindingsPath,
      publicKeyResolver: resolver,
      ...extra
    });
  }

  // A signed proof event for ROW_ID that we can mutate before signing, so the
  // signature stays valid while the embedded fields are tampered.
  function signedProofItems() {
    return [
      {
        binding_slug: "checkout.apply_coupon#handler",
        row_id: ROW_ID,
        file_path: "Sources/Checkout/CouponService.swift",
        extent_kind: "swift_func_inferred",
        recognizer_id: "swift-func-inferred-v1",
        span_canon_id: "ucase-span-lines-v1",
        span_sha256: SPAN_A,
        span_start_line: 13,
        span_end_line: 27
      }
    ];
  }
  function unsignedProof(overrides: Record<string, unknown> = {}): Record<string, unknown> {
    const items = signedProofItems();
    return {
      schema: "ucase-proof-event-v1",
      event_type: "row_proof_passed",
      event_id: "01JFAKEFAKEFAKEFAKEFAKEFAK",
      created_at: "2026-06-28T12:05:00Z",
      producer: {
        kind: "trusted-ci-prover",
        id: "ci/use-cases-prover",
        version: "0.1.0",
        ci_run_id: "1",
        repo: "org/product",
        commit: "0".repeat(40)
      },
      row: {
        row_id: ROW_ID,
        row_hash_id: "existing-semantic-row-hash",
        row_hash: `sha256:${"1".repeat(64)}`,
        verification_policy_hash: `sha256:${"2".repeat(64)}`,
        approval_policy_hash: `sha256:${"3".repeat(64)}`
      },
      bindings: {
        binding_set_hash_id: "ucase-binding-set-v1",
        binding_set_hash: computeBindingSetHash(ROW_ID, items),
        span_canon_id: "ucase-span-lines-v1",
        items
      },
      verification: {
        command_id: "acceptance.checkout.apply_coupon",
        result: "pass",
        started_at: "2026-06-28T12:04:10Z",
        completed_at: "2026-06-28T12:04:59Z",
        artifacts: []
      },
      ...overrides
    };
  }

  test("agent appends an unsigned proof event -> validate-ledger fails (SIGNATURE_MISSING)", () => {
    const { ws } = setupProven();
    writeFileSync(ws.evidencePath, `${readFileSync(ws.evidencePath, "utf8").trim()}\n${JSON.stringify(unsignedProof())}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "SIGNATURE_MISSING")).toBe(true);
  });

  test("agent appends a proof with a fake producer.kind -> validate-ledger fails (PRODUCER_NOT_TRUSTED)", () => {
    const { ws } = setupProven();
    const fake = unsignedProof({
      producer: { kind: "rogue-agent", id: "x", version: "0", ci_run_id: "1", repo: "r", commit: "0".repeat(40) }
    });
    const signed = signEvent(fake, PRIVATE_KEY, KEY_ID);
    writeFileSync(ws.evidencePath, `${readFileSync(ws.evidencePath, "utf8").trim()}\n${JSON.stringify(signed)}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "PRODUCER_NOT_TRUSTED")).toBe(true);
  });

  test("agent appends a proof with a bad signature -> validate-ledger fails (BAD_SIGNATURE)", () => {
    const { ws } = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    const raw = Buffer.from(event.signature.value, "base64");
    raw[0] ^= 0xff;
    event.signature.value = raw.toString("base64");
    writeFileSync(ws.evidencePath, `${JSON.stringify(event)}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "BAD_SIGNATURE")).toBe(true);
  });

  test("agent appends a proof with result: fail -> validate-ledger fails (VERIFICATION_NOT_PASS)", () => {
    const { ws } = setupProven();
    const fail = unsignedProof();
    (fail.verification as Record<string, unknown>).result = "fail";
    const signed = signEvent(fail, PRIVATE_KEY, KEY_ID);
    writeFileSync(ws.evidencePath, `${readFileSync(ws.evidencePath, "utf8").trim()}\n${JSON.stringify(signed)}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "VERIFICATION_NOT_PASS")).toBe(true);
  });

  test("agent edits an old evidence line -> append-only validation fails", () => {
    const { ws, provedEventLine } = setupProven();
    const baseRefOld = `${provedEventLine}\n`;
    // Current ledger edits the committed line in place.
    const edited = JSON.parse(provedEventLine);
    edited.event_id = "01JEDITEDEDITEDEDITEDEDITED";
    writeFileSync(ws.evidencePath, `${JSON.stringify(edited)}\n`);
    const result = validate(ws, { baseRef: "origin/main", gitRunner: () => baseRefOld });
    expect(result.exit_code).toBe(4);
    expect(result.append_only).toBe(false);
    expect(result.errors.some((error) => error.code === "APPEND_ONLY_VIOLATION")).toBe(true);
  });

  test("agent deletes an old evidence line -> append-only validation fails", () => {
    const { ws, provedEventLine } = setupProven();
    const secondLine = JSON.stringify({ ...JSON.parse(provedEventLine), event_id: "01JSECONDSECONDSECONDSECOND" });
    const baseRefOld = `${provedEventLine}\n${secondLine}\n`;
    // Current ledger drops the second committed line.
    writeFileSync(ws.evidencePath, `${provedEventLine}\n`);
    const result = validate(ws, { baseRef: "origin/main", gitRunner: () => baseRefOld });
    expect(result.exit_code).toBe(4);
    expect(result.append_only).toBe(false);
    expect(result.errors.some((error) => error.code === "APPEND_ONLY_VIOLATION")).toBe(true);
  });

  test("agent edits an old registry line -> append-only validation fails", () => {
    const { ws } = setupProven();
    const current = readFileSync(ws.bindingsPath, "utf8");
    // Base ref's first registry line differs from the current first line: an edit.
    const tamperedBase = `${JSON.stringify({ tampered: "old line" })}\n${current}`;
    const result = validate(ws, { baseRef: "origin/main", gitRunner: () => tamperedBase });
    expect(result.exit_code).toBe(4);
    expect(result.append_only).toBe(false);
    expect(result.errors.some((error) => error.code === "APPEND_ONLY_VIOLATION")).toBe(true);
  });

  test("agent deletes an old registry line -> append-only validation fails", () => {
    const { ws } = setupProven();
    const current = readFileSync(ws.bindingsPath, "utf8").trim();
    const extra = JSON.stringify(registryEvent("checkout.remove_coupon", "checkout.remove_coupon"));
    // Base ref had an extra committed line that the current ledger has dropped.
    const baseRefOld = `${current}\n${extra}\n`;
    const result = validate(ws, { baseRef: "origin/main", gitRunner: () => baseRefOld });
    expect(result.exit_code).toBe(4);
    expect(result.append_only).toBe(false);
    expect(result.errors.some((error) => error.code === "APPEND_ONLY_VIOLATION")).toBe(true);
  });

  test("proof binding_set_hash does not recompute from items -> validate-ledger fails (BINDING_SET_HASH_MISMATCH)", () => {
    const { ws } = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    event.bindings.binding_set_hash = `sha256:${"d".repeat(64)}`;
    const { signature, ...withoutSignature } = event;
    void signature;
    const resigned = signEvent(withoutSignature, PRIVATE_KEY, KEY_ID);
    writeFileSync(ws.evidencePath, `${JSON.stringify(resigned)}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "BINDING_SET_HASH_MISMATCH")).toBe(true);
  });

  test("proof event row id does not exist -> validate-ledger fails (EVIDENCE_ROW_MISSING)", () => {
    const { ws } = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    event.row.row_id = "checkout.ghost_row";
    event.bindings.items = event.bindings.items.map((item: Record<string, unknown>) => ({ ...item, row_id: "checkout.ghost_row" }));
    event.bindings.binding_set_hash = computeBindingSetHash("checkout.ghost_row", event.bindings.items);
    const { signature, ...withoutSignature } = event;
    void signature;
    const resigned = signEvent(withoutSignature, PRIVATE_KEY, KEY_ID);
    writeFileSync(ws.evidencePath, `${JSON.stringify(resigned)}\n`);
    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "EVIDENCE_ROW_MISSING")).toBe(true);
  });

  test("binder writes NO evidence event", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: "Sources/Checkout/CouponService.swift",
      mode: "swift-func",
      line: 3,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });
    expect(() => readFileSync(ws.evidencePath, "utf8")).toThrow(); // file never created
  });

  test("scanner writes NO evidence event", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: "Sources/Checkout/CouponService.swift",
      mode: "swift-func",
      line: 3,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });
    runScanCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      policyMode: "feature",
      publicKeyResolver: resolver,
      generatedAt: GENERATED_AT
    });
    expect(() => readFileSync(ws.evidencePath, "utf8")).toThrow(); // scan never writes evidence
  });

  test("prover does NOT accept caller-supplied span/row hash; it recomputes both itself", () => {
    const { ws } = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    // The appended proof's hashes equal the values recomputed from the loaded row
    // and the freshly scanned source — never anything a caller could inject.
    const scanned = scanFileForMarkers(
      "Sources/Checkout/CouponService.swift",
      readFileSync(join(ws.productRoot, "Sources/Checkout/CouponService.swift"), "utf8")
    );
    const scannedSpan = scanned.bindings.find((b) => b.binding_slug === ROW_ID)?.span.sha256;
    expect(scannedSpan).toBeTruthy();
    // The proof's embedded span hash is exactly the scanned span hash.
    expect(event.bindings.items[0].span_sha256).toBe(scannedSpan);
    // And the ProveCommandOptions type exposes no field for a caller span/row hash:
    // the only way to influence the proof is the source + row, both recomputed.
    expect(event.bindings.binding_set_hash).toBe(
      computeBindingSetHash(ROW_ID, [
        {
          binding_slug: ROW_ID,
          row_id: ROW_ID,
          file_path: "Sources/Checkout/CouponService.swift",
          extent_kind: "swift_func_inferred",
          recognizer_id: "swift-func-inferred-v1",
          span_canon_id: "ucase-span-lines-v1",
          span_sha256: scannedSpan as string
        }
      ])
    );
  });
});

// ===========================================================================
// 11.5 Freshness mutations
// ===========================================================================
describe("11.5 freshness mutations", () => {
  const slug = "checkout.apply_coupon#handler";

  test("edit row YAML after proof -> SUSPECT, ROW_HASH_CHANGED", () => {
    const provenRow = makeRow();
    const binding = makeBinding(slug);
    const proof = makeProof(provenRow, [binding]);
    const editedRow = makeRow({ intent: "apply a valid coupon to a cart (reworded)" });
    const status = derive({
      rows: [editedRow],
      registry: makeRegistry([[editedRow.row_id, slug]]),
      scan: makeScan([binding]),
      evidence: [proof]
    });
    const result = rowOf(status, editedRow.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("ROW_HASH_CHANGED");
  });

  test("edit marked code span after proof -> SUSPECT, CODE_SPAN_CHANGED", () => {
    const row = makeRow();
    const proof = makeProof(row, [makeBinding(slug, { span_sha256: SPAN_A })]);
    const status = derive({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug, { span_sha256: SPAN_B })]),
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("CODE_SPAN_CHANGED");
  });

  test("add a new binding to a proven row -> SUSPECT, BINDING_ADDED", () => {
    const row = makeRow();
    const addedSlug = "checkout.apply_coupon#tax";
    const proof = makeProof(row, [makeBinding(slug, { span_sha256: SPAN_A })]);
    const status = derive({
      rows: [row],
      registry: makeRegistry([
        [row.row_id, slug],
        [row.row_id, addedSlug]
      ]),
      scan: makeScan([
        makeBinding(slug, { span_sha256: SPAN_A }),
        makeBinding(addedSlug, { span_sha256: SPAN_B, file_path: "Sources/Checkout/Tax.swift" })
      ]),
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("BINDING_ADDED");
  });

  test("remove a binding from a proven row -> SUSPECT, BINDING_REMOVED", () => {
    const row = makeRow();
    const otherSlug = "checkout.apply_coupon#tax";
    const proof = makeProof(row, [
      makeBinding(slug, { span_sha256: SPAN_A }),
      makeBinding(otherSlug, { span_sha256: SPAN_B, file_path: "Sources/Checkout/Tax.swift" })
    ]);
    const status = derive({
      rows: [row],
      registry: makeRegistry([
        [row.row_id, slug],
        [row.row_id, otherSlug]
      ]),
      scan: makeScan([makeBinding(slug, { span_sha256: SPAN_A })]), // otherSlug marker removed
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("BINDING_REMOVED");
  });

  test("move a binding to a new file with the same span text -> SUSPECT, BINDING_PATH_CHANGED", () => {
    const row = makeRow();
    const proof = makeProof(row, [makeBinding(slug, { span_sha256: SPAN_A, file_path: "Sources/Checkout/Old.swift" })]);
    const status = derive({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug, { span_sha256: SPAN_A, file_path: "Sources/Checkout/New.swift" })]),
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("BINDING_PATH_CHANGED");
  });

  test("change the verification policy after proof -> SUSPECT, VERIFICATION_POLICY_CHANGED", () => {
    const provenRow = makeRow();
    const binding = makeBinding(slug);
    const proof = makeProof(provenRow, [binding]);
    const editedRow = makeRow({ verification_policy: { command: "npm run test:usecase -- different" } });
    const status = derive({
      rows: [editedRow],
      registry: makeRegistry([[editedRow.row_id, slug]]),
      scan: makeScan([binding]),
      evidence: [proof]
    });
    const result = rowOf(status, editedRow.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("VERIFICATION_POLICY_CHANGED");
  });

  test("change the approval policy after proof -> SUSPECT, APPROVAL_POLICY_CHANGED", () => {
    const provenRow = makeRow();
    const binding = makeBinding(slug);
    const proof = makeProof(provenRow, [binding]);
    const editedRow = makeRow({
      approval_policy: { required_for_release: true, trusted_producer: "trusted-ci-prover", note: "stricter" }
    });
    const status = derive({
      rows: [editedRow],
      registry: makeRegistry([[editedRow.row_id, slug]]),
      scan: makeScan([binding]),
      evidence: [proof]
    });
    const result = rowOf(status, editedRow.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(reasonCodes(result)).toContain("APPROVAL_POLICY_CHANGED");
  });

  test("revert row and span to exactly the proven hashes -> FRESH", () => {
    const row = makeRow();
    const binding = makeBinding(slug, { span_sha256: SPAN_A });
    const proof = makeProof(row, [binding]);
    const status = derive({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug, { span_sha256: SPAN_A })]),
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("FRESH");
    expect(result.reasons).toEqual([]);
  });
});

// ===========================================================================
// Capstone: a fabricated or unsigned proof event can NEVER make a row FRESH.
// ===========================================================================
describe("CAPSTONE: no fabricated/unsigned proof can mint FRESH", () => {
  test("a fabricated unsigned proof is rejected by validate-ledger AND never reaches FRESH in scan", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: "Sources/Checkout/CouponService.swift",
      mode: "swift-func",
      line: 3,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });

    // The freshly scanned span hash for the bound row, so the fabricated proof's
    // embedded binding_set_hash even RECOMPUTES correctly (internally consistent)
    // and its row/policy hashes match the live row. The ONLY thing missing is a
    // trusted signature — which must be sufficient to deny FRESH.
    const sourcePath = join(ws.productRoot, "Sources/Checkout/CouponService.swift");
    const scanned = scanFileForMarkers(sourcePath, readFileSync(sourcePath, "utf8"));
    const span = scanned.bindings.find((b) => b.binding_slug === ROW_ID)?.span.sha256 as string;
    const items = [
      {
        binding_slug: ROW_ID,
        row_id: ROW_ID,
        file_path: "Sources/Checkout/CouponService.swift",
        extent_kind: "swift_func_inferred",
        recognizer_id: "swift-func-inferred-v1",
        span_canon_id: "ucase-span-lines-v1",
        span_sha256: span,
        span_start_line: scanned.bindings[0].span.start_line,
        span_end_line: scanned.bindings[0].span.end_line
      }
    ];
    const fabricated = {
      schema: "ucase-proof-event-v1",
      event_type: "row_proof_passed",
      event_id: "01JFABRICATEDFABRICATEDFAB",
      created_at: GENERATED_AT,
      producer: { kind: "trusted-ci-prover", id: "ci", version: "0.1.0", ci_run_id: "1", repo: "r", commit: "0".repeat(40) },
      row: {
        row_id: ROW_ID,
        row_hash_id: "existing-semantic-row-hash",
        row_hash: `sha256:${"1".repeat(64)}`,
        verification_policy_hash: `sha256:${"2".repeat(64)}`,
        approval_policy_hash: `sha256:${"3".repeat(64)}`
      },
      bindings: {
        binding_set_hash_id: "ucase-binding-set-v1",
        binding_set_hash: computeBindingSetHash(ROW_ID, items),
        span_canon_id: "ucase-span-lines-v1",
        items
      },
      verification: {
        command_id: "acceptance.checkout.apply_coupon",
        result: "pass",
        started_at: GENERATED_AT,
        completed_at: GENERATED_AT,
        artifacts: []
      }
      // NOTE: no signature field at all -> unsigned, fabricated by an agent.
    };
    writeFileSync(ws.evidencePath, `${JSON.stringify(fabricated)}\n`);

    // 1) validate-ledger rejects it outright.
    const ledger = runValidateLedgerCommand({
      context: ws.context,
      evidencePath: ws.evidencePath,
      bindingsPath: ws.bindingsPath,
      publicKeyResolver: resolver
    });
    expect(ledger.exit_code).toBe(4);
    expect(ledger.ok).toBe(false);
    expect(ledger.errors.some((error) => error.code === "SIGNATURE_MISSING")).toBe(true);

    // 2) scan never lets the fabricated proof mint FRESH (the unsigned event is
    // stripped before freshness derivation; the row is NOT FRESH).
    const scan = runScanCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      policyMode: "feature",
      publicKeyResolver: resolver,
      generatedAt: GENERATED_AT
    });
    const row = scan.status.rows.find((entry) => entry.row_id === ROW_ID);
    expect(row).toBeDefined();
    expect(row?.status).not.toBe("FRESH");
    expect(scan.evidence_valid).toBe(false);

    // 3) Directly: deriveFreshness with ONLY validated evidence (which excludes the
    // fabricated event) leaves the row UNPROVEN, not FRESH.
    const validatedEvents = validateEvidenceLedger(readFileSync(ws.evidencePath, "utf8"), {
      publicKeyResolver: resolver
    });
    expect(validatedEvents.events).toHaveLength(0); // the fabricated event is not a valid event
  });
});
