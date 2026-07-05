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
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { describe, expect, test } from "vitest";
import {
  keyringAssuranceTierResolver,
  keyringWebAuthnCredentialResolver,
  keyringResolver,
  type Keyring
} from "../../src/markers/index.js";
import { canonicalJson } from "../../src/markers/canonicalJson.js";
import {
  mintApprovalRequest,
  signApprovalToken,
  verifyApprovalToken,
  type ApprovalRequestBinding,
  type ApprovalToken
} from "../../src/showcase/approvalToken.js";

type TestAssuranceMethod = "automation" | "same_channel" | "os_presence";
type TestWebAuthnAlg = -7 | -8;

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

// A keyring where the trusted human key carries max_assurance_tier
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
        max_assurance_tier: "trusted_host_user_presence"
      },
      {
        key_id: "automation-key-1",
        algorithm: "ed25519",
        public_key: OTHER_KEY.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        max_assurance_tier: "untrusted_automation"
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

function b64url(bytes: Buffer): string {
  return bytes.toString("base64url");
}

function sha256(bytes: Buffer | string): Buffer {
  return createHash("sha256").update(bytes).digest();
}

function webAuthnChallenge(binding: ApprovalRequestBinding): string {
  return b64url(sha256(canonicalJson(binding)));
}

function webAuthnCredential(alg: TestWebAuthnAlg): {
  alg: TestWebAuthnAlg;
  credentialId: string;
  publicKeySpki: string;
  privateKey: ReturnType<typeof generateKeyPairSync>["privateKey"];
} {
  const pair =
    alg === -7
      ? generateKeyPairSync("ec", { namedCurve: "P-256" })
      : generateKeyPairSync("ed25519");
  return {
    alg,
    credentialId: alg === -7 ? "credential-es256" : "credential-ed25519",
    publicKeySpki: b64url(pair.publicKey.export({ type: "spki", format: "der" })),
    privateKey: pair.privateKey
  };
}

function webAuthnKeyring(credential: ReturnType<typeof webAuthnCredential>): Keyring {
  return {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      {
        algorithm: "webauthn",
        credential_id: credential.credentialId,
        credential_public_key_alg: credential.alg,
        credential_public_key_spki: credential.publicKeySpki,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active",
        max_assurance_tier: "webauthn_hardware"
      }
    ]
  };
}

function webAuthnToken(options: {
  credential: ReturnType<typeof webAuthnCredential>;
  binding?: ApprovalRequestBinding;
  challenge?: string;
  flags?: number;
  tamperSignature?: boolean;
  tamperAuthenticatorData?: boolean;
}): ApprovalToken {
  const binding = options.binding ?? liveBinding();
  const request = mintApprovalRequest({ binding, nowMs: Date.parse(IN_WINDOW), ttlMinutes: 15 });
  const flags = options.flags ?? 0x05; // UP + UV
  const authenticatorData = Buffer.concat([
    sha256("use-cases.dev"),
    Buffer.from([flags]),
    Buffer.from([0, 0, 0, 1])
  ]);
  const clientDataJson = Buffer.from(
    JSON.stringify({
      type: "webauthn.get",
      challenge: options.challenge ?? webAuthnChallenge(binding),
      origin: "https://use-cases.dev"
    }),
    "utf8"
  );
  const signatureBase = Buffer.concat([authenticatorData, sha256(clientDataJson)]);
  const signatureValue =
    options.credential.alg === -7
      ? sign("SHA256", signatureBase, options.credential.privateKey)
      : sign(null, signatureBase, options.credential.privateKey);
  const signatureBytes = Buffer.from(signatureValue);
  if (options.tamperSignature) {
    signatureBytes[0] ^= 0xff;
  }
  const authenticatorDataBytes = Buffer.from(authenticatorData);
  if (options.tamperAuthenticatorData) {
    authenticatorDataBytes[0] ^= 0xff;
  }
  return {
    approval_token_schema: "ucase-approval-token-v1",
    binding,
    jti: request.jti,
    iat: request.iat,
    exp: request.exp,
    created_at: request.iat,
    decision: "approved",
    assurance_method: "webauthn",
    assurance_tier: "webauthn_hardware",
    signature: {
      alg: "webauthn",
      credential_id: options.credential.credentialId,
      authenticator_data: b64url(authenticatorDataBytes),
      client_data_json: b64url(clientDataJson),
      signature: b64url(signatureBytes)
    }
  };
}

// Mint a request (plugin-side nonce/iat/exp), then sign it out-of-band into a
// token with a decision + the key that produced the signature.
function mintAndSign(options: {
  binding?: ApprovalRequestBinding;
  privateKeyPem?: string;
  keyId?: string;
  decision?: ApprovalToken["decision"];
  assuranceMethod?: TestAssuranceMethod;
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
    keyId: options.keyId ?? "human-key-1",
    assuranceMethod: options.assuranceMethod
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

describe("Part 2 assurance method + keyring cap", () => {
  function cappedKeyring(
    keyId: string,
    publicKeyPem: string,
    maxTier: NonNullable<Keyring["keys"][number]["max_assurance_tier"]>
  ): Keyring {
    return {
      keyring_schema_id: "ucase-public-key-registry-v1",
      keys: [
        {
          key_id: keyId,
          algorithm: "ed25519",
          public_key: publicKeyPem,
          valid_from: "2026-01-01T00:00:00Z",
          valid_until: null,
          status: "active",
          max_assurance_tier: maxTier
        }
      ]
    };
  }

  test("method=same_channel on a trusted-host capped key verifies at the claimed same-channel tier", () => {
    const token = mintAndSign({ assuranceMethod: "same_channel" });
    const cap = cappedKeyring("human-key-1", TRUSTED_KEY.publicKeyPem, "trusted_host_user_presence");
    const result = verifyApprovalToken({
      token,
      resolver: keyringResolver(cap),
      tierResolver: keyringAssuranceTierResolver(cap),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "same_channel_operator_confirmation"
    });

    expect(result.ok).toBe(true);
    expect(result.ok === true && result.assurance_tier).toBe("same_channel_operator_confirmation");
  });

  test("method=os_presence over a same-channel capped key is rejected as ASSURANCE_OVER_CLAIM", () => {
    const token = mintAndSign({ assuranceMethod: "os_presence" });
    const cap = cappedKeyring("human-key-1", TRUSTED_KEY.publicKeyPem, "same_channel_operator_confirmation");
    const result = verifyApprovalToken({
      token,
      resolver: keyringResolver(cap),
      tierResolver: keyringAssuranceTierResolver(cap),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "same_channel_operator_confirmation"
    });

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("ASSURANCE_OVER_CLAIM");
  });

  test("approval floor is enforced against the token's claimed tier, not the key cap", () => {
    const token = mintAndSign({ assuranceMethod: "same_channel" });
    const cap = cappedKeyring("human-key-1", TRUSTED_KEY.publicKeyPem, "trusted_host_user_presence");
    const result = verifyApprovalToken({
      token,
      resolver: keyringResolver(cap),
      tierResolver: keyringAssuranceTierResolver(cap),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "trusted_host_user_presence"
    });

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("ASSURANCE_TOO_LOW");
  });

  test("legacy tokens without assurance_method verify at the signing key's cap tier", () => {
    const token = mintAndSign();
    const cap = cappedKeyring("human-key-1", TRUSTED_KEY.publicKeyPem, "same_channel_operator_confirmation");
    const result = verifyApprovalToken({
      token,
      resolver: keyringResolver(cap),
      tierResolver: keyringAssuranceTierResolver(cap),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: "same_channel_operator_confirmation"
    });

    expect(result.ok).toBe(true);
    expect(result.ok === true && result.assurance_tier).toBe("same_channel_operator_confirmation");
  });
});

describe("Part 3 WebAuthn hardware approval assertions", () => {
  function verifyWebAuthn(
    token: ApprovalToken,
    keyringValue: Keyring,
    floor: "same_channel_operator_confirmation" | "trusted_host_user_presence" | "webauthn_hardware" = "webauthn_hardware"
  ) {
    return verifyApprovalToken({
      token,
      resolver: keyringResolver(keyringValue),
      tierResolver: keyringAssuranceTierResolver(keyringValue),
      webauthnCredentialResolver: keyringWebAuthnCredentialResolver(keyringValue),
      liveBinding: liveBinding(),
      isNonceBurned: () => false,
      nowMs: Date.parse(IN_WINDOW),
      assuranceFloor: floor
    });
  }

  test("valid ES256 and Ed25519 WebAuthn assertions verify at webauthn_hardware", () => {
    for (const credential of [webAuthnCredential(-7), webAuthnCredential(-8)]) {
      const token = webAuthnToken({ credential });
      const result = verifyWebAuthn(token, webAuthnKeyring(credential));

      expect(result.ok).toBe(true);
      expect(result.ok === true && result.key_id).toBe(credential.credentialId);
      expect(result.ok === true && result.assurance_tier).toBe("webauthn_hardware");
    }
  });

  test("a WebAuthn assertion with the wrong binding challenge is rejected", () => {
    const credential = webAuthnCredential(-7);
    const token = webAuthnToken({ credential, challenge: b64url(sha256("wrong-run")) });
    const result = verifyWebAuthn(token, webAuthnKeyring(credential));

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("WEBAUTHN_CHALLENGE_MISMATCH");
  });

  test("a WebAuthn assertion without UP or UV is rejected fail-closed", () => {
    const credential = webAuthnCredential(-7);

    const noUserPresence = verifyWebAuthn(
      webAuthnToken({ credential, flags: 0x04 }),
      webAuthnKeyring(credential)
    );
    expect(noUserPresence.ok).toBe(false);
    expect(noUserPresence.ok === false && noUserPresence.code).toBe("WEBAUTHN_USER_NOT_PRESENT");

    const noUserVerification = verifyWebAuthn(
      webAuthnToken({ credential, flags: 0x01 }),
      webAuthnKeyring(credential)
    );
    expect(noUserVerification.ok).toBe(false);
    expect(noUserVerification.ok === false && noUserVerification.code).toBe("WEBAUTHN_USER_NOT_VERIFIED");
  });

  test("tampered WebAuthn signature or authenticatorData is rejected", () => {
    const credential = webAuthnCredential(-8);

    const badSignature = verifyWebAuthn(
      webAuthnToken({ credential, tamperSignature: true }),
      webAuthnKeyring(credential)
    );
    expect(badSignature.ok).toBe(false);
    expect(badSignature.ok === false && badSignature.code).toBe("WEBAUTHN_BAD_SIGNATURE");

    const badAuthenticatorData = verifyWebAuthn(
      webAuthnToken({ credential, tamperAuthenticatorData: true }),
      webAuthnKeyring(credential)
    );
    expect(badAuthenticatorData.ok).toBe(false);
    expect(badAuthenticatorData.ok === false && badAuthenticatorData.code).toBe("WEBAUTHN_BAD_SIGNATURE");
  });

  test("a WebAuthn credential that is not pinned in the keyring is rejected", () => {
    const credential = webAuthnCredential(-7);
    const otherCredential = { ...webAuthnCredential(-7), credentialId: "other-credential-es256" };
    const token = webAuthnToken({ credential });
    const result = verifyWebAuthn(token, webAuthnKeyring(otherCredential));

    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("WEBAUTHN_CREDENTIAL_UNKNOWN");
  });

  test("a WebAuthn token still passes through max cap and approval floor checks", () => {
    const credential = webAuthnCredential(-7);
    const keyringValue = webAuthnKeyring(credential);
    const underHardwareFloor = verifyWebAuthn(webAuthnToken({ credential }), keyringValue, "trusted_host_user_presence");

    expect(underHardwareFloor.ok).toBe(true);
    expect(underHardwareFloor.ok === true && underHardwareFloor.assurance_tier).toBe("webauthn_hardware");

    const cappedTooLow: Keyring = {
      ...keyringValue,
      keys: [
        {
          ...keyringValue.keys[0],
          max_assurance_tier: "trusted_host_user_presence"
        }
      ]
    };
    const overClaim = verifyWebAuthn(webAuthnToken({ credential }), cappedTooLow);

    expect(overClaim.ok).toBe(false);
    expect(overClaim.ok === false && overClaim.code).toBe("ASSURANCE_OVER_CLAIM");
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
