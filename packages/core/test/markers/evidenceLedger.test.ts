import { generateKeyPairSync } from "node:crypto";
import { describe, expect, test } from "vitest";
import {
  computeBindingSetHash,
  EvidenceErrorCode,
  proofSigningPayload,
  readEvidenceJsonl,
  signEvent,
  validateEvidenceLedger,
  validateProofEventValue,
  verifyEvent,
  type ProofBindingItem,
  type PublicKeyResolver
} from "../../src/markers/index.js";

// A throwaway ed25519 keypair for the trusted CI signer. Tests generate the
// keypair, sign a fixture, then verify against the public key (spec amendment 3).
const KEY_ID = "trusted-ci-2026-01";
const { publicKey, privateKey } = generateKeyPairSync("ed25519");
const publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
const privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();

// Resolver that knows only KEY_ID; any other key_id is unknown -> INVALID.
const resolver: PublicKeyResolver = (keyId) => (keyId === KEY_ID ? publicKeyPem : undefined);

const ROW_ID = "checkout.apply_coupon";

function bindingItem(overrides: Partial<ProofBindingItem> = {}): ProofBindingItem {
  return {
    binding_slug: "checkout.apply_coupon#handler",
    row_id: ROW_ID,
    file_path: "Sources/Checkout/CouponService.swift",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v2",
    span_sha256: `sha256:${"a".repeat(64)}`,
    span_start_line: 13,
    span_end_line: 27,
    ...overrides
  };
}

// Build an unsigned proof event whose embedded binding_set_hash correctly
// recomputes from its items (spec 5.4). Override fields to construct mutations.
function unsignedEvent(
  overrides: { items?: ProofBindingItem[]; bindingSetHash?: string; rowId?: string } = {}
): Record<string, unknown> {
  const items = overrides.items ?? [bindingItem()];
  const rowId = overrides.rowId ?? ROW_ID;
  const bindingSetHash = overrides.bindingSetHash ?? computeBindingSetHash(rowId, items);
  return {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: "01JABCDEFAAAAAAAAAAAAAAAAAA",
    created_at: "2026-06-28T12:05:00Z",
    producer: {
      kind: "trusted-ci-prover",
      id: "github-actions/use-cases-prover",
      version: "0.1.0",
      ci_run_id: "123456789",
      repo: "org/product",
      commit: "0123456789abcdef0123456789abcdef01234567"
    },
    row: {
      row_id: rowId,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: `sha256:${"b".repeat(64)}`,
      verification_policy_hash: `sha256:${"c".repeat(64)}`,
      approval_policy_hash: `sha256:${"d".repeat(64)}`
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash: bindingSetHash,
      span_canon_id: "ucase-span-lines-v2",
      items
    },
    verification: {
      command_id: "acceptance.checkout.apply_coupon",
      result: "pass",
      started_at: "2026-06-28T12:04:10Z",
      completed_at: "2026-06-28T12:04:59Z",
      context_hash_id: "ucase-verification-context-hash-v1",
      context_hash: `sha256:${"f".repeat(64)}`,
      artifacts: [
        {
          kind: "junit",
          path: "artifacts/use-cases/checkout.apply_coupon/junit.xml",
          sha256: `sha256:${"e".repeat(64)}`
        }
      ]
    }
  };
}

function signedEvent(
  overrides: Parameters<typeof unsignedEvent>[0] = {}
): Record<string, unknown> {
  return signEvent(unsignedEvent(overrides), privateKeyPem, KEY_ID) as Record<string, unknown>;
}

function jsonl(...events: Array<Record<string, unknown>>): string {
  return events.map((e) => JSON.stringify(e)).join("\n");
}

function codes(errors: Array<{ code: string }>): string[] {
  return errors.map((e) => e.code);
}

describe("proofs.jsonl reader", () => {
  test("parses one event per line and tolerates a trailing newline", () => {
    const text = `${jsonl(signedEvent())}\n`;
    const result = readEvidenceJsonl(text);
    expect(result.errors).toEqual([]);
    expect(result.lines).toHaveLength(1);
    expect(result.lines[0].line).toBe(1);
  });

  test("reports a JSON parse error with the offending 1-based line number", () => {
    const text = [
      JSON.stringify(signedEvent()),
      "{ not valid json",
      JSON.stringify(signedEvent())
    ].join("\n");
    const result = readEvidenceJsonl(text);
    expect(result.lines).toHaveLength(2);
    expect(result.errors).toHaveLength(1);
    expect(result.errors[0].code).toBe(EvidenceErrorCode.JSON_PARSE_ERROR);
    expect(result.errors[0].line).toBe(2);
  });
});

describe("ed25519 sign / verify (spec 5.3)", () => {
  test("signing payload excludes the signature field", () => {
    const signed = signedEvent();
    const withoutSig = { ...signed };
    delete withoutSig.signature;
    // Payload computed from the signed event equals the payload of the event
    // without a signature -> signature field is excluded from the material.
    expect(proofSigningPayload(signed)).toBe(proofSigningPayload(withoutSig));
  });

  test("a freshly signed event verifies against its public key", () => {
    const result = verifyEvent(signedEvent(), resolver);
    expect(result.ok).toBe(true);
  });
});

describe("validateEvidenceLedger acceptance criteria (Phase 5)", () => {
  // 1. A validly signed proof event passes.
  test("1: valid signed proof event passes", () => {
    const result = validateEvidenceLedger(jsonl(signedEvent()), { publicKeyResolver: resolver });
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.events).toHaveLength(1);
    expect(result.summary.proof_events_checked).toBe(1);
    expect(result.summary.proof_events_valid).toBe(1);
  });

  // 2. An unsigned proof event fails.
  test("2: unsigned proof event fails (SIGNATURE_MISSING)", () => {
    const unsigned = unsignedEvent(); // no signature field at all
    const result = validateEvidenceLedger(jsonl(unsigned), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.SIGNATURE_MISSING);
  });

  // 3. A proof event with a bad / tampered signature fails.
  test("3: tampered signature fails (BAD_SIGNATURE)", () => {
    const signed = signedEvent();
    // Flip the signature value while keeping it valid base64 of the right length.
    const sig = signed.signature as { alg: string; key_id: string; value: string };
    const raw = Buffer.from(sig.value, "base64");
    raw[0] ^= 0xff;
    const tampered = {
      ...signed,
      signature: { ...sig, value: raw.toString("base64") }
    };
    const result = validateEvidenceLedger(jsonl(tampered), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.BAD_SIGNATURE);
  });

  test("3b: unknown key_id fails (UNKNOWN_KEY_ID)", () => {
    const signed = signEvent(unsignedEvent(), privateKeyPem, "some-other-key") as Record<
      string,
      unknown
    >;
    const result = validateEvidenceLedger(jsonl(signed), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.UNKNOWN_KEY_ID);
  });

  // 4. An edited old evidence line fails (append-only).
  test("4: editing an old evidence line fails (APPEND_ONLY_VIOLATION)", () => {
    const first = signedEvent();
    const baseRefOldText = jsonl(first);
    // The committed line is changed in place (re-signed different event).
    const edited = signedEvent({ rowId: ROW_ID });
    const editedLine = JSON.stringify({ ...edited, event_id: "01JEDITEDEDITEDEDITEDEDITED" });
    const current = `${editedLine}\n${JSON.stringify(signedEvent())}`;
    const result = validateEvidenceLedger(current, {
      publicKeyResolver: resolver,
      baseRefOldText
    });
    expect(result.ok).toBe(false);
    expect(result.append_only).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.APPEND_ONLY_VIOLATION);
  });

  // 5. A deleted old evidence line fails (append-only).
  test("5: deleting an old evidence line fails (APPEND_ONLY_VIOLATION)", () => {
    const a = JSON.stringify(signedEvent());
    const b = JSON.stringify({ ...signedEvent(), event_id: "01JSECONDSECONDSECONDSECOND" });
    const baseRefOldText = `${a}\n${b}`;
    const current = a; // second committed line removed
    const result = validateEvidenceLedger(current, {
      publicKeyResolver: resolver,
      baseRefOldText
    });
    expect(result.ok).toBe(false);
    expect(result.append_only).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.APPEND_ONLY_VIOLATION);
  });

  test("5b: pure append of a new line passes append-only", () => {
    const a = JSON.stringify(signedEvent());
    const baseRefOldText = a;
    const b = JSON.stringify({ ...signedEvent(), event_id: "01JAPPENDAPPENDAPPENDAPPEND" });
    const current = `${a}\n${b}`;
    const result = validateEvidenceLedger(current, {
      publicKeyResolver: resolver,
      baseRefOldText
    });
    expect(result.append_only).toBe(true);
    expect(codes(result.errors)).not.toContain(EvidenceErrorCode.APPEND_ONLY_VIOLATION);
  });

  // 6. A proof event whose binding_set_hash does not recompute from its items fails.
  test("6: bad binding_set_hash fails (BINDING_SET_HASH_MISMATCH)", () => {
    const bad = signedEvent({ bindingSetHash: `sha256:${"f".repeat(64)}` });
    const result = validateEvidenceLedger(jsonl(bad), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.BINDING_SET_HASH_MISMATCH);
  });

  // 7. An old proof whose span differs from current code does NOT fail validation.
  test("7: span_sha256 differing from current code is NOT an INVALID here", () => {
    // The event is internally consistent: its binding_set_hash recomputes from
    // its own items. validate-ledger must NOT compare span_sha256 to current code
    // (that drift is SUSPECT, left to the Phase 6 freshness machine).
    const drifted = signedEvent({
      items: [bindingItem({ span_sha256: `sha256:${"9".repeat(64)}` })]
    });
    const result = validateEvidenceLedger(jsonl(drifted), { publicKeyResolver: resolver });
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
    expect(codes(result.errors)).not.toContain(EvidenceErrorCode.BINDING_SET_HASH_MISMATCH);
  });

  // producer.kind != trusted-ci-prover fails.
  test("producer.kind not trusted-ci-prover fails (PRODUCER_NOT_TRUSTED)", () => {
    const base = unsignedEvent();
    (base.producer as Record<string, unknown>).kind = "rogue-agent";
    const signed = signEvent(base, privateKeyPem, KEY_ID) as Record<string, unknown>;
    const result = validateEvidenceLedger(jsonl(signed), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.PRODUCER_NOT_TRUSTED);
  });

  // verification.result == "fail" fails.
  test('verification.result "fail" fails (VERIFICATION_NOT_PASS)', () => {
    const base = unsignedEvent();
    (base.verification as Record<string, unknown>).result = "fail";
    const signed = signEvent(base, privateKeyPem, KEY_ID) as Record<string, unknown>;
    const result = validateEvidenceLedger(jsonl(signed), { publicKeyResolver: resolver });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.VERIFICATION_NOT_PASS);
  });

  test("unknown YAML row fails when yamlRowIds provided (EVIDENCE_ROW_MISSING)", () => {
    const result = validateEvidenceLedger(jsonl(signedEvent()), {
      publicKeyResolver: resolver,
      yamlRowIds: new Set(["checkout.remove_coupon"])
    });
    expect(result.ok).toBe(false);
    expect(codes(result.errors)).toContain(EvidenceErrorCode.EVIDENCE_ROW_MISSING);
  });

  test("known YAML row passes the row-existence check", () => {
    const result = validateEvidenceLedger(jsonl(signedEvent()), {
      publicKeyResolver: resolver,
      yamlRowIds: new Set([ROW_ID])
    });
    expect(result.ok).toBe(true);
  });

  test("summary tallies valid and invalid events with error codes", () => {
    const good = signedEvent();
    const bad = signedEvent({ bindingSetHash: `sha256:${"0".repeat(64)}` });
    const result = validateEvidenceLedger(jsonl(good, bad), { publicKeyResolver: resolver });
    expect(result.summary.proof_events_checked).toBe(2);
    expect(result.summary.proof_events_valid).toBe(1);
    expect(result.summary.proof_events_invalid).toBe(1);
    expect(result.summary.errors_by_code[EvidenceErrorCode.BINDING_SET_HASH_MISMATCH]).toBe(1);
  });
});

describe("validateProofEventValue (single event)", () => {
  test("multi-binding set hashes order-independently and validates", () => {
    const items = [
      bindingItem({ binding_slug: "checkout.apply_coupon#handler" }),
      bindingItem({
        binding_slug: "checkout.apply_coupon#tax",
        file_path: "Sources/Checkout/CouponRules.swift",
        extent_kind: "explicit",
        recognizer_id: "explicit-span-v1"
      })
    ];
    const signed = signEvent(unsignedEvent({ items }), privateKeyPem, KEY_ID) as Record<
      string,
      unknown
    >;
    const result = validateProofEventValue(signed, 1, { publicKeyResolver: resolver });
    expect(result.ok).toBe(true);
    expect(result.event).not.toBeNull();
  });
});
