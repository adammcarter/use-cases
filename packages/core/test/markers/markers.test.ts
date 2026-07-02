import { describe, expect, test } from "vitest";
import { computeSemanticHash } from "../../src/schema/index.js";
import {
  BINDING_SET_HASH_ID,
  ROW_HASH_ID,
  buildBindingSetMaterial,
  canonicalJson,
  canonicalJsonSha256,
  computeApprovalPolicyHash,
  computeBindingSetHash,
  computeRowHash,
  computeVerificationPolicyHash,
  sha256,
  validateBindingRegistryEvent,
  validateFreshnessStatus,
  validateProofEvent,
  type BindingSetInputMember
} from "../../src/markers/index.js";

const HEX64 = /^sha256:[0-9a-f]{64}$/;
const ZERO_HASH = `sha256:${"0".repeat(64)}`;

function bindingMember(
  overrides: Partial<BindingSetInputMember> & { binding_slug: string }
): BindingSetInputMember {
  return {
    row_id: "checkout.apply_coupon",
    file_path: "Sources/Checkout/CouponService.swift",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v1",
    span_sha256: `sha256:${"a".repeat(64)}`,
    ...overrides
  };
}

describe("canonical_json", () => {
  test("sorts object keys and emits no insignificant whitespace", () => {
    expect(canonicalJson({ b: 1, a: 2 })).toBe('{"a":2,"b":1}');
  });

  test("is order-independent for object keys", () => {
    expect(canonicalJson({ a: 1, b: { d: 4, c: 3 } })).toBe(
      canonicalJson({ b: { c: 3, d: 4 }, a: 1 })
    );
  });

  test("preserves array order as given", () => {
    expect(canonicalJson([3, 1, 2])).toBe("[3,1,2]");
    expect(canonicalJson([1, 2, 3])).not.toBe(canonicalJson([3, 1, 2]));
  });

  test("drops undefined-valued keys", () => {
    expect(canonicalJson({ a: 1, b: undefined })).toBe('{"a":1}');
  });

  test("rejects non-finite numbers", () => {
    expect(() => canonicalJson({ a: Number.POSITIVE_INFINITY })).toThrow();
    expect(() => canonicalJson({ a: Number.NaN })).toThrow();
  });
});

describe("sha256 helper", () => {
  test("returns the sha256:<hex> form", () => {
    expect(sha256("")).toMatch(HEX64);
    // Known vector: sha256 of the empty string.
    expect(sha256("")).toBe(
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
  });

  test("canonicalJsonSha256 hashes the canonical form", () => {
    expect(canonicalJsonSha256({ a: 1 })).toBe(sha256('{"a":1}'));
  });
});

describe("row hash adapter", () => {
  test("reuses the existing semantic-hash algorithm", () => {
    const row = { id: "checkout.apply_coupon", intent: "apply coupon" };
    expect(computeRowHash(row)).toBe(computeSemanticHash(row));
    expect(computeRowHash(row)).toMatch(HEX64);
  });

  test("ROW_HASH_ID names the existing algorithm", () => {
    expect(ROW_HASH_ID).toBe("existing-semantic-row-hash");
  });
});

describe("policy hashes", () => {
  test("verification policy hash is deterministic and key-order independent", () => {
    const a = computeVerificationPolicyHash({ command: "npm test", retries: 1 });
    const b = computeVerificationPolicyHash({ retries: 1, command: "npm test" });
    expect(a).toBe(b);
    expect(a).toMatch(HEX64);
  });

  test("approval policy hash changes when the policy changes", () => {
    const a = computeApprovalPolicyHash({ required_for_release: true });
    const b = computeApprovalPolicyHash({ required_for_release: false });
    expect(a).not.toBe(b);
  });
});

describe("binding_set_hash (spec 4.5)", () => {
  const handler = bindingMember({
    binding_slug: "checkout.apply_coupon#handler",
    span_sha256: `sha256:${"1".repeat(64)}`
  });
  const tax = bindingMember({
    binding_slug: "checkout.apply_coupon#tax",
    file_path: "Sources/Checkout/CouponRules.swift",
    extent_kind: "explicit",
    recognizer_id: "explicit-span-v1",
    span_sha256: `sha256:${"2".repeat(64)}`
  });

  test("same binding set in different order hashes identically", () => {
    const forward = computeBindingSetHash("checkout.apply_coupon", [handler, tax]);
    const reversed = computeBindingSetHash("checkout.apply_coupon", [tax, handler]);
    expect(forward).toBe(reversed);
    expect(forward).toMatch(HEX64);
  });

  test("material schema id and sort order are stable", () => {
    const material = buildBindingSetMaterial("checkout.apply_coupon", [tax, handler]);
    expect(material.schema).toBe(BINDING_SET_HASH_ID);
    expect(material.bindings.map((b) => b.binding_slug)).toEqual([
      "checkout.apply_coupon#handler",
      "checkout.apply_coupon#tax"
    ]);
  });

  test("changing span_sha256 changes binding_set_hash", () => {
    const base = computeBindingSetHash("checkout.apply_coupon", [handler]);
    const mutated = computeBindingSetHash("checkout.apply_coupon", [
      bindingMember({ binding_slug: handler.binding_slug, span_sha256: `sha256:${"9".repeat(64)}` })
    ]);
    expect(mutated).not.toBe(base);
  });

  test("changing file_path changes binding_set_hash", () => {
    const base = computeBindingSetHash("checkout.apply_coupon", [handler]);
    const mutated = computeBindingSetHash("checkout.apply_coupon", [
      bindingMember({
        binding_slug: handler.binding_slug,
        span_sha256: handler.span_sha256,
        file_path: "Sources/Checkout/Other.swift"
      })
    ]);
    expect(mutated).not.toBe(base);
  });

  test("changing line numbers does NOT change binding_set_hash", () => {
    const withLines = computeBindingSetHash("checkout.apply_coupon", [
      { ...handler, span_start_line: 13, span_end_line: 27, start_byte: 355 }
    ]);
    const withDifferentLines = computeBindingSetHash("checkout.apply_coupon", [
      { ...handler, span_start_line: 99, span_end_line: 140, start_byte: 9000 }
    ]);
    const withoutLines = computeBindingSetHash("checkout.apply_coupon", [handler]);
    expect(withLines).toBe(withoutLines);
    expect(withDifferentLines).toBe(withoutLines);
  });
});

describe("binding registry event schema", () => {
  function validRegistryEvent(): Record<string, unknown> {
    return {
      schema: "ucase-binding-registry-event-v1",
      event_type: "binding_registered",
      event_id: "01JABCDEF00000000000000000",
      created_at: "2026-06-28T12:00:00Z",
      created_by: { tool: "use-case-matrix", command: "bind", version: "0.1.0" },
      row_id: "checkout.apply_coupon",
      binding_slug: "checkout.apply_coupon#handler",
      reason: "initial_bind"
    };
  }

  test("a valid registry event passes", () => {
    expect(validateBindingRegistryEvent(validRegistryEvent()).ok).toBe(true);
  });

  test("an invalid registry event fails schema validation (missing binding_slug)", () => {
    const event = validRegistryEvent();
    delete event.binding_slug;
    expect(validateBindingRegistryEvent(event).ok).toBe(false);
  });

  test("an invalid registry event fails schema validation (wrong event_type)", () => {
    expect(
      validateBindingRegistryEvent({ ...validRegistryEvent(), event_type: "binding_removed" }).ok
    ).toBe(false);
  });

  test("an invalid registry event fails schema validation (forbidden extra field)", () => {
    expect(
      validateBindingRegistryEvent({ ...validRegistryEvent(), proof: "smuggled" }).ok
    ).toBe(false);
  });
});

describe("proof event schema", () => {
  function validProofEvent(): Record<string, unknown> {
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
        row_id: "checkout.apply_coupon",
        row_hash_id: "existing-semantic-row-hash",
        row_hash: ZERO_HASH,
        verification_policy_hash: ZERO_HASH,
        approval_policy_hash: ZERO_HASH
      },
      bindings: {
        binding_set_hash_id: "ucase-binding-set-v1",
        binding_set_hash: ZERO_HASH,
        span_canon_id: "ucase-span-lines-v1",
        items: [
          {
            binding_slug: "checkout.apply_coupon#handler",
            row_id: "checkout.apply_coupon",
            file_path: "Sources/Checkout/CouponService.swift",
            extent_kind: "swift_func_inferred",
            recognizer_id: "swift-func-inferred-v1",
            span_canon_id: "ucase-span-lines-v1",
            span_sha256: ZERO_HASH,
            span_start_line: 13,
            span_end_line: 27
          }
        ]
      },
      verification: {
        command_id: "acceptance.checkout.apply_coupon",
        result: "pass",
        started_at: "2026-06-28T12:04:10Z",
        completed_at: "2026-06-28T12:04:59Z",
        context_hash_id: "ucase-verification-context-hash-v1",
        context_hash: ZERO_HASH,
        artifacts: [
          {
            kind: "junit",
            path: "artifacts/use-cases/checkout.apply_coupon/junit.xml",
            sha256: ZERO_HASH
          }
        ]
      },
      signature: { alg: "ed25519", key_id: "trusted-ci-2026-01", value: "base64sig" }
    };
  }

  test("a valid proof event passes", () => {
    const result = validateProofEvent(validProofEvent());
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  test("an invalid proof event fails schema validation (unsigned)", () => {
    const event = validProofEvent();
    delete event.signature;
    expect(validateProofEvent(event).ok).toBe(false);
  });

  test("an invalid proof event fails schema validation (result not pass)", () => {
    const event = validProofEvent();
    (event.verification as Record<string, unknown>).result = "fail";
    expect(validateProofEvent(event).ok).toBe(false);
  });

  test("an invalid proof event fails schema validation (untrusted producer kind)", () => {
    const event = validProofEvent();
    (event.producer as Record<string, unknown>).kind = "agent";
    expect(validateProofEvent(event).ok).toBe(false);
  });

  test("an invalid proof event fails schema validation (malformed binding_set_hash)", () => {
    const event = validProofEvent();
    (event.bindings as Record<string, unknown>).binding_set_hash = "not-a-hash";
    expect(validateProofEvent(event).ok).toBe(false);
  });
});

describe("freshness status schema", () => {
  function validStatus(): Record<string, unknown> {
    return {
      schema: "ucase-freshness-status-v1",
      generated_at: "2026-06-28T12:10:00Z",
      tool: { name: "use-case-matrix", version: "0.1.0" },
      product_root: "/workspace/product",
      policy_mode: "feature",
      guard_ok: true,
      summary: { fresh: 1, suspect: 0, unproven: 0, unbound: 3, invalid: 0, policy_blocked: 0 },
      integrity_errors: [],
      rows: [
        {
          row_id: "checkout.apply_coupon",
          row_hash: ZERO_HASH,
          verification_policy_hash: ZERO_HASH,
          approval_policy_hash: ZERO_HASH,
          status: "FRESH",
          policy_block: false,
          reasons: [],
          known_binding_slugs: ["checkout.apply_coupon#handler"],
          current_binding_slugs: ["checkout.apply_coupon#handler"],
          missing_registered_binding_slugs: [],
          unregistered_current_binding_slugs: [],
          current_binding_set_hash: ZERO_HASH,
          current_bindings: [
            {
              binding_slug: "checkout.apply_coupon#handler",
              file_path: "Sources/Checkout/CouponService.swift",
              extent_kind: "swift_func_inferred",
              recognizer_id: "swift-func-inferred-v1",
              span_canon_id: "ucase-span-lines-v1",
              span_sha256: ZERO_HASH,
              span_start_line: 13,
              span_end_line: 27
            }
          ],
          matching_proof_event: {
            event_id: "01JABCDEFAAAAAAAAAAAAAAAAAA",
            created_at: "2026-06-28T12:05:00Z",
            commit: "0123456789abcdef0123456789abcdef01234567"
          },
          latest_trusted_proof_event: {
            event_id: "01JABCDEFAAAAAAAAAAAAAAAAAA",
            created_at: "2026-06-28T12:05:00Z",
            commit: "0123456789abcdef0123456789abcdef01234567"
          },
          required_action: null
        }
      ]
    };
  }

  test("a valid freshness status passes", () => {
    const result = validateFreshnessStatus(validStatus());
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  test("a suspect row with reason objects passes", () => {
    const status = validStatus();
    status.rows = [
      {
        row_id: "checkout.apply_coupon",
        status: "SUSPECT",
        policy_block: false,
        reasons: [
          {
            code: "CODE_SPAN_CHANGED",
            binding_slug: "checkout.apply_coupon#handler",
            expected_span_sha256: "sha256:old",
            actual_span_sha256: "sha256:new"
          }
        ],
        required_action: "use-cases prove --row checkout.apply_coupon"
      }
    ];
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("an invalid status fails schema validation (bad policy_mode)", () => {
    expect(validateFreshnessStatus({ ...validStatus(), policy_mode: "bogus" }).ok).toBe(false);
  });

  test("an invalid status fails schema validation (unknown row status)", () => {
    const status = validStatus();
    (status.rows as Array<Record<string, unknown>>)[0].status = "MAYBE";
    expect(validateFreshnessStatus(status).ok).toBe(false);
  });
});
