// F3 — trusted human approval as a SIGNED, run-bound, single-use token.
//
// The security spine. An in-session agent may REQUEST approval but a real human
// MINTS it out-of-band by signing an approval_token with an ed25519 key that
// lives OUTSIDE the agent's granted scope. The plugin then verifies the token
// against the SAME ed25519 machinery used for proof events (signEvent /
// verifyEvent + a fail-closed keyring) AND independently re-checks every bound
// field, the nonce, the expiry, and the key's assurance tier.
//
// These are the MUST-REJECT / MUST-ACCEPT cases from the F3 TDD matrix.
import { generateKeyPairSync } from "node:crypto";
import { describe, expect, test } from "vitest";
import {
  keyringAssuranceTierResolver,
  keyringResolver,
  type Keyring
} from "../../src/markers/index.js";
import {
  mintApprovalRequest,
  signApprovalToken,
  verifyApprovalToken,
  type ApprovalRequestBinding,
  type ApprovalToken
} from "../../src/showcase/approvalToken.js";

// ---------------------------------------------------------------------------
// Fixtures: two keys. TRUSTED = a host_signed_approval_token tier key (the human
// custody key, out of the agent's scope). AGENT = a key the in-session agent
// COULD reach — it is deliberately NOT trusted at the human-presence tier.
// ---------------------------------------------------------------------------
function ed25519Pem(): { publicKeyPem: string; privateKeyPem: string } {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString()
  };
}

const TRUSTED_KEY = ed25519Pem();
const OTHER_KEY = ed25519Pem();

const IN_WINDOW = "2026-06-28T12:05:00.000Z";

// A keyring where the trusted human key carries assurance_tier
// trusted_host_user_presence, and a second key carries only untrusted_automation.
function keyring(): Keyring {
  return {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      {
        key_id: "human-key-1",
        algorithm: "ed25519",
        public_key: TRUSTED_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        assurance_tier: "trusted_host_user_presence"
      },
      {
        key_id: "automation-key-1",
        algorithm: "ed25519",
        public_key: OTHER_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        assurance_tier: "untrusted_automation"
      }
    ]
  };
}

// The live run values the plugin will independently recompute the token against.
function liveBinding(overrides: Partial<ApprovalRequestBinding> = {}): ApprovalRequestBinding {
  return {
    run_id: "run.alpha",
    finish_event_id: "evt.run.alpha.7",
    plan_content_hash: "sha256:plan-alpha",
    ledger_head_hash: "sha256:head-alpha",
    evidence_digest: "sha256:evidence-alpha",
    git_commit: "0123456789abcdef0123456789abcdef01234567",
    ci_freshness_digest: "sha256:ci-alpha",
    ...overrides
  };
}

// Mint a request (plugin-side nonce/iat/exp), then sign it out-of-band into a
// token with a decision + the key that produced the signature.
function mintAndSign(options: {
  binding?: ApprovalRequestBinding;
  privateKeyPem?: string;
  keyId?: string;
  decision?: ApprovalToken["decision"];
  nowMs?: number;
  ttlMinutes?: number;
} = {}): ApprovalToken {
  const now = options.nowMs ?? Date.parse(IN_WINDOW);
  const request = mintApprovalRequest({
    binding: options.binding ?? liveBinding(),
    nowMs: now,
    ttlMinutes: options.ttlMinutes ?? 15
  });
  return signApprovalToken({
    request,
    decision: options.decision ?? "approved",
    privateKey: options.privateKeyPem ?? TRUSTED_KEY.privateKeyPem,
    keyId: options.keyId ?? "human-key-1"
  });
}

const resolver = () => keyringResolver(keyring());
const tierResolver = () => keyringAssuranceTierResolver(keyring());

describe("F3 verifyApprovalToken — MUST ACCEPT (j)", () => {
  test("a token bound to the live run, fresh nonce, unexpired, trusted in-window key -> accepted", () => {
    const token = mintAndSign();
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(true);
    expect(result.ok === true && result.decision).toBe("approved");
    expect(result.ok === true && result.jti).toBe(token.jti);
    expect(result.ok === true && result.assurance_tier).toBe("trusted_host_user_presence");
  });
});

describe("F3 verifyApprovalToken — MUST REJECT", () => {
  test("(g) tampered payload bytes -> BAD_SIGNATURE", () => {
    const token = mintAndSign();
    const tampered: ApprovalToken = { ...token, decision: "rejected" };
    const result = verifyApprovalToken({
      token: tampered,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("BAD_SIGNATURE");
  });

  test("(f) unknown / out-of-window / revoked key_id -> UNKNOWN_KEY_ID (fail-closed)", () => {
    const token = mintAndSign({ keyId: "no-such-key" });
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("UNKNOWN_KEY_ID");
  });

  test("(d) expired token (exp in the past) -> TOKEN_EXPIRED", () => {
    const token = mintAndSign({ nowMs: Date.parse(IN_WINDOW), ttlMinutes: 15 });
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      // 16 minutes after mint -> past the 15-minute exp.
      nowMs: Date.parse(IN_WINDOW) + 16 * 60_000,
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("TOKEN_EXPIRED");
  });

  test("(c) replay: a validly-signed token whose nonce is already burned -> NONCE_BURNED", () => {
    const token = mintAndSign();
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: (jti) => jti === token.jti,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("NONCE_BURNED");
  });

  test("(e) wrong-run: token minted for run A presented for run B -> BINDING_MISMATCH", () => {
    const token = mintAndSign({ binding: liveBinding({ run_id: "run.alpha" }) });
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      // The LIVE run is a different run entirely.
      liveBinding: liveBinding({ run_id: "run.beta" }),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("BINDING_MISMATCH");
  });

  test("(e) rebind: mismatched finish_event_id / ledger_head_hash / evidence_digest / git_commit -> BINDING_MISMATCH", () => {
    for (const field of [
      "finish_event_id",
      "ledger_head_hash",
      "evidence_digest",
      "git_commit",
      "plan_content_hash",
      "ci_freshness_digest"
    ] as const) {
      const token = mintAndSign();
      const result = verifyApprovalToken({
        token,
        resolver: resolver(),
      tierResolver: tierResolver(),
        liveBinding: liveBinding({ [field]: "sha256:DIFFERENT" }),
        isNonceBurned: () => false,
        nowMs: Date.parse(IN_WINDOW),
        assuranceFloor: "trusted_host_user_presence"
      });
      expect(result.ok, `field ${field} must mismatch`).toBe(false);
      expect(result.ok === false && result.code).toBe("BINDING_MISMATCH");
    }
  });

  test("(h) an untrusted_automation key does NOT meet a trusted_host_user_presence floor -> ASSURANCE_TOO_LOW", () => {
    // Signed by the automation key (tier untrusted_automation in the keyring).
    const token = mintAndSign({
      privateKeyPem: OTHER_KEY.privateKeyPem,
      keyId: "automation-key-1"
    });
    const result = verifyApprovalToken({
      token,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("ASSURANCE_TOO_LOW");
  });

  test("(l) KEY-CUSTODY: a signer WITHOUT the trusted key cannot produce an accepted approval", () => {
    // The attacker owns OTHER_KEY but tries to pass it off under the trusted
    // key_id. The keyring binds human-key-1 -> the real trusted public key, so
    // the forged signature fails to verify against it.
    const request = mintApprovalRequest({ binding: liveBinding(), nowMs: Date.parse(IN_WINDOW), ttlMinutes: 15 });
    const forged = signApprovalToken({
      request,
      decision: "approved",
      privateKey: OTHER_KEY.privateKeyPem,
      keyId: "human-key-1" // claims the trusted id it does not hold the key for
    });
    const result = verifyApprovalToken({
      token: forged,
      resolver: resolver(),
      tierResolver: tierResolver(),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("BAD_SIGNATURE");
  });
});

describe("F3 mintApprovalRequest — the nonce is PLUGIN-minted and single-use-shaped", () => {
  test("each mint produces a distinct, non-empty jti and an exp strictly after iat", () => {
    const a = mintApprovalRequest({ binding: liveBinding(), nowMs: Date.parse(IN_WINDOW), ttlMinutes: 15 });
    const b = mintApprovalRequest({ binding: liveBinding(), nowMs: Date.parse(IN_WINDOW), ttlMinutes: 15 });
    expect(a.jti).toBeTruthy();
    expect(b.jti).toBeTruthy();
    expect(a.jti).not.toBe(b.jti);
    expect(Date.parse(a.exp)).toBeGreaterThan(Date.parse(a.iat));
  });
});
