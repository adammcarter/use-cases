// F3 — trusted human approval as a SIGNED, run-bound, single-use token.
//
// THE MODEL: an agent / CLI / MCP may only REQUEST approval. A real human MINTS
// it out-of-band by signing an approval_token with an ed25519 key held OUTSIDE
// the in-session agent's granted filesystem/env scope. The plugin then verifies
// the token with the SAME crypto used for proof events (verifyEvent) + the
// fail-closed keyring, AND independently re-checks every bound field, the nonce,
// the expiry, and the key's keyring-bound assurance tier.
//
// Reuses proofSignature.ts (signEvent/verifyEvent — sign over
// canonicalJson(event minus signature)) and keyring.ts VERBATIM. No new crypto.
import { createHash, createPublicKey, randomUUID, verify } from "node:crypto";
import {
  signEvent,
  verifyEvent,
  type PemOrKeyObject,
  type ProofSignatureBlock,
  type PublicKeyResolver
} from "../markers/proofSignature.js";
import type {
  AssuranceTierResolver,
  KeyringAssuranceTier,
  WebAuthnCredential,
  WebAuthnCredentialResolver
} from "../markers/keyring.js";
import { canonicalJson } from "../markers/canonicalJson.js";
import {
  assuranceTierForMethod,
  isAssuranceMethod,
  isAssuranceTier,
  normalizeAssuranceTier,
  tierMeetsFloor,
  AssuranceMethod,
  AssuranceTier
} from "./approvalTiers.js";

// The bound run facts a request/token pins itself to. Every one of these is
// re-checked against the LIVE run at verify time; any drift => BINDING_MISMATCH.
export interface ApprovalRequestBinding {
  run_id: string;
  finish_event_id: string;
  plan_content_hash: string;
  ledger_head_hash: string;
  evidence_digest: string;
  git_commit: string;
  ci_freshness_digest: string;
}

export type ApprovalDecision = "approved" | "approved_with_known_gaps" | "rejected";

export interface WebAuthnSignatureBlock {
  alg: "webauthn";
  credential_id: string;
  authenticator_data: string; // base64url authenticatorData
  client_data_json: string; // base64url clientDataJSON
  signature: string; // base64url signature over authenticatorData || SHA-256(clientDataJSON)
}

export type ApprovalTokenSignatureBlock = ProofSignatureBlock | WebAuthnSignatureBlock;

// The PLUGIN-minted request an agent/CLI/MCP emits. The nonce (jti) is minted
// HERE by the plugin, never supplied by the caller, so it is genuinely single-use.
export interface ApprovalRequest {
  approval_request_schema: "ucase-approval-request-v1";
  binding: ApprovalRequestBinding;
  jti: string; // single-use nonce, plugin-minted
  iat: string; // ISO-8601 issued-at
  exp: string; // ISO-8601 expiry
}

// The out-of-band signed token a human produces from a request. `created_at`
// mirrors `iat` so verifyEvent can thread it to the keyring's validity window.
export interface ApprovalToken {
  approval_token_schema: "ucase-approval-token-v1";
  binding: ApprovalRequestBinding;
  jti: string;
  iat: string;
  exp: string;
  created_at: string;
  decision: ApprovalDecision;
  assurance_method?: AssuranceMethod;
  assurance_tier?: AssuranceTier;
  signature: ApprovalTokenSignatureBlock;
}

export type WebAuthnAssertionInput = Omit<WebAuthnSignatureBlock, "alg">;

export type ApprovalTokenFailureCode =
  | "SIGNATURE_MISSING"
  | "SIGNATURE_ALG_UNSUPPORTED"
  | "UNKNOWN_KEY_ID"
  | "BAD_SIGNATURE"
  | "BINDING_MISMATCH"
  | "TOKEN_EXPIRED"
  | "NONCE_BURNED"
  | "ASSURANCE_OVER_CLAIM"
  | "ASSURANCE_TOO_LOW"
  | "WEBAUTHN_CREDENTIAL_UNKNOWN"
  | "WEBAUTHN_ASSERTION_INVALID"
  | "WEBAUTHN_CHALLENGE_MISMATCH"
  | "WEBAUTHN_USER_NOT_PRESENT"
  | "WEBAUTHN_USER_NOT_VERIFIED"
  | "WEBAUTHN_BAD_SIGNATURE"
  | "MALFORMED_TOKEN";

export type VerifyApprovalTokenResult =
  | {
      ok: true;
      jti: string;
      decision: ApprovalDecision;
      key_id: string;
      assurance_tier: AssuranceTier;
    }
  | { ok: false; code: ApprovalTokenFailureCode; message: string };

// Plugin-side: mint a request pinned to the live run with a fresh single-use
// nonce and an expiry `ttlMinutes` out. The caller does NOT get to choose the
// nonce (that would defeat single-use); the plugin owns it.
export function mintApprovalRequest(options: {
  binding: ApprovalRequestBinding;
  nowMs?: number;
  ttlMinutes?: number;
  jti?: string; // test-only override; production omits it
}): ApprovalRequest {
  const now = options.nowMs ?? Date.now();
  const ttl = options.ttlMinutes ?? 15;
  return {
    approval_request_schema: "ucase-approval-request-v1",
    binding: { ...options.binding },
    jti: options.jti ?? `approval.${randomUUID()}`,
    iat: new Date(now).toISOString(),
    exp: new Date(now + ttl * 60_000).toISOString()
  };
}

// Out-of-band (in the HUMAN's own shell): turn a request into a signed token.
// The ed25519 private key lives outside the agent's scope; signEvent covers the
// whole token minus its signature.
export function signApprovalToken(options: {
  request: ApprovalRequest;
  decision: ApprovalDecision;
  privateKey: PemOrKeyObject;
  keyId: string;
  assuranceMethod?: AssuranceMethod;
}): ApprovalToken {
  if (options.assuranceMethod === AssuranceMethod.WEBAUTHN) {
    throw new Error("ed25519 approval tokens cannot claim webauthn assurance");
  }
  const assurance =
    options.assuranceMethod === undefined
      ? {}
      : {
          assurance_method: options.assuranceMethod,
          assurance_tier: assuranceTierForMethod(options.assuranceMethod)
        };
  const unsigned = {
    approval_token_schema: "ucase-approval-token-v1" as const,
    binding: { ...options.request.binding },
    jti: options.request.jti,
    iat: options.request.iat,
    exp: options.request.exp,
    // created_at drives the keyring window; it must equal iat so the moment of
    // signing is what the window is checked against.
    created_at: options.request.iat,
    decision: options.decision,
    ...assurance
  };
  return signEvent(unsigned, options.privateKey, options.keyId) as ApprovalToken;
}

// Boundary helper used by `uc approve-run --webauthn-assertion`: the actual
// authenticator ceremony is out of scope. The caller supplies the platform
// assertion; verification happens in verifyApprovalToken against pinned trust.
export function buildWebAuthnApprovalToken(options: {
  request: ApprovalRequest;
  decision: ApprovalDecision;
  assertion: WebAuthnAssertionInput;
}): ApprovalToken {
  return {
    approval_token_schema: "ucase-approval-token-v1",
    binding: { ...options.request.binding },
    jti: options.request.jti,
    iat: options.request.iat,
    exp: options.request.exp,
    created_at: options.request.iat,
    decision: options.decision,
    assurance_method: AssuranceMethod.WEBAUTHN,
    assurance_tier: assuranceTierForMethod(AssuranceMethod.WEBAUTHN),
    signature: {
      alg: "webauthn",
      credential_id: options.assertion.credential_id,
      authenticator_data: options.assertion.authenticator_data,
      client_data_json: options.assertion.client_data_json,
      signature: options.assertion.signature
    }
  };
}

const BINDING_FIELDS: (keyof ApprovalRequestBinding)[] = [
  "run_id",
  "finish_event_id",
  "plan_content_hash",
  "ledger_head_hash",
  "evidence_digest",
  "git_commit",
  "ci_freshness_digest"
];

function claimedAssuranceTier(
  token: ApprovalToken,
  maxTier: AssuranceTier
): { ok: true; tier: AssuranceTier } | { ok: false; message: string } {
  if (token.assurance_method === undefined) {
    return { ok: true, tier: maxTier };
  }
  if (!isAssuranceMethod(token.assurance_method)) {
    return { ok: false, message: `unsupported assurance_method ${String(token.assurance_method)}` };
  }
  if (token.assurance_method === AssuranceMethod.WEBAUTHN) {
    return { ok: false, message: "ed25519 signatures cannot claim webauthn assurance" };
  }
  if (!isAssuranceTier(token.assurance_tier)) {
    return { ok: false, message: "approval token assurance_tier is missing or unsupported" };
  }
  const derivedTier = assuranceTierForMethod(token.assurance_method);
  if (token.assurance_tier !== derivedTier) {
    return {
      ok: false,
      message: `approval token assurance_tier ${token.assurance_tier} does not match method ${token.assurance_method}`
    };
  }
  return { ok: true, tier: token.assurance_tier };
}

function claimedWebAuthnAssuranceTier(
  token: ApprovalToken
): { ok: true; tier: AssuranceTier } | { ok: false; message: string } {
  if (token.assurance_method === undefined && token.assurance_tier === undefined) {
    return { ok: true, tier: AssuranceTier.WEBAUTHN_HARDWARE };
  }
  if (token.assurance_method !== AssuranceMethod.WEBAUTHN) {
    return { ok: false, message: "webauthn signature must use assurance_method webauthn" };
  }
  if (token.assurance_tier !== AssuranceTier.WEBAUTHN_HARDWARE) {
    return { ok: false, message: "webauthn signature must use assurance_tier webauthn_hardware" };
  }
  return { ok: true, tier: AssuranceTier.WEBAUTHN_HARDWARE };
}

function sha256(bytes: Buffer | string): Buffer {
  return createHash("sha256").update(bytes).digest();
}

function approvalBindingChallenge(binding: ApprovalRequestBinding): string {
  return sha256(canonicalJson(binding)).toString("base64url");
}

function decodeBase64Url(value: unknown): Buffer | null {
  if (typeof value !== "string" || value.length === 0 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    return null;
  }
  try {
    const decoded = Buffer.from(value, "base64url");
    return decoded.length > 0 && decoded.toString("base64url") === value ? decoded : null;
  } catch {
    return null;
  }
}

function parseWebAuthnClientData(
  clientDataJson: Buffer,
  expectedChallenge: string
):
  | { ok: true }
  | { ok: false; code: ApprovalTokenFailureCode; message: string } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(clientDataJson.toString("utf8"));
  } catch {
    return { ok: false, code: "WEBAUTHN_ASSERTION_INVALID", message: "webauthn client_data_json is not valid JSON" };
  }
  if (!parsed || typeof parsed !== "object") {
    return { ok: false, code: "WEBAUTHN_ASSERTION_INVALID", message: "webauthn clientDataJSON is not an object" };
  }
  const clientData = parsed as { type?: unknown; challenge?: unknown };
  if (clientData.type !== "webauthn.get") {
    return { ok: false, code: "WEBAUTHN_ASSERTION_INVALID", message: "webauthn clientDataJSON.type must be webauthn.get" };
  }
  if (typeof clientData.challenge !== "string" || clientData.challenge !== expectedChallenge) {
    return {
      ok: false,
      code: "WEBAUTHN_CHALLENGE_MISMATCH",
      message: "webauthn clientDataJSON.challenge does not match this approval binding"
    };
  }
  return { ok: true };
}

function parseWebAuthnAuthenticatorData(
  authenticatorData: Buffer
):
  | { ok: true }
  | { ok: false; code: ApprovalTokenFailureCode; message: string } {
  if (authenticatorData.length < 37) {
    return { ok: false, code: "WEBAUTHN_ASSERTION_INVALID", message: "webauthn authenticator_data is too short" };
  }
  const flags = authenticatorData[32];
  if ((flags & 0x01) === 0) {
    return { ok: false, code: "WEBAUTHN_USER_NOT_PRESENT", message: "webauthn assertion did not set the UP flag" };
  }
  if ((flags & 0x04) === 0) {
    return { ok: false, code: "WEBAUTHN_USER_NOT_VERIFIED", message: "webauthn assertion did not set the UV flag" };
  }
  return { ok: true };
}

function verifyWebAuthnSignature(options: {
  credential: WebAuthnCredential;
  signatureBase: Buffer;
  signature: Buffer;
}): boolean {
  const spki = decodeBase64Url(options.credential.credential_public_key_spki);
  if (!spki) {
    return false;
  }
  try {
    const publicKey = createPublicKey({ key: spki, type: "spki", format: "der" });
    const algorithm = options.credential.credential_public_key_alg === -7 ? "SHA256" : null;
    return verify(algorithm, options.signatureBase, publicKey, options.signature);
  } catch {
    return false;
  }
}

function verifyWebAuthnAssertion(options: {
  token: ApprovalToken;
  credentialResolver?: WebAuthnCredentialResolver;
  liveBinding: ApprovalRequestBinding;
}):
  | { ok: true; key_id: string; maxTier: KeyringAssuranceTier }
  | { ok: false; code: ApprovalTokenFailureCode; message: string } {
  const signature = options.token.signature as Partial<WebAuthnSignatureBlock> | undefined;
  if (
    !signature ||
    signature.alg !== "webauthn" ||
    typeof signature.credential_id !== "string" ||
    typeof signature.authenticator_data !== "string" ||
    typeof signature.client_data_json !== "string" ||
    typeof signature.signature !== "string"
  ) {
    return { ok: false, code: "SIGNATURE_MISSING", message: "approval token has no usable webauthn signature block" };
  }

  const credential = options.credentialResolver?.(signature.credential_id, options.token.created_at);
  if (!credential) {
    return {
      ok: false,
      code: "WEBAUTHN_CREDENTIAL_UNKNOWN",
      message: `unknown or unpinned webauthn credential_id: ${signature.credential_id}`
    };
  }

  const authenticatorData = decodeBase64Url(signature.authenticator_data);
  const clientDataJson = decodeBase64Url(signature.client_data_json);
  const assertionSignature = decodeBase64Url(signature.signature);
  if (!authenticatorData || !clientDataJson || !assertionSignature) {
    return { ok: false, code: "WEBAUTHN_ASSERTION_INVALID", message: "webauthn assertion fields must be base64url bytes" };
  }

  const clientData = parseWebAuthnClientData(clientDataJson, approvalBindingChallenge(options.liveBinding));
  if (!clientData.ok) {
    return clientData;
  }
  const authenticator = parseWebAuthnAuthenticatorData(authenticatorData);
  if (!authenticator.ok) {
    return authenticator;
  }

  const signatureBase = Buffer.concat([authenticatorData, sha256(clientDataJson)]);
  if (!verifyWebAuthnSignature({ credential, signatureBase, signature: assertionSignature })) {
    return {
      ok: false,
      code: "WEBAUTHN_BAD_SIGNATURE",
      message: `webauthn signature for credential_id ${signature.credential_id} did not verify`
    };
  }

  return { ok: true, key_id: signature.credential_id, maxTier: credential.max_assurance_tier };
}

// Plugin-side VERIFY: the whole gate. Order is deliberate — signature/key first
// (so a tampered payload or an unknown key surfaces as a crypto failure), then
// the independent binding / expiry / single-use / assurance-tier checks.
export function verifyApprovalToken(options: {
  token: ApprovalToken;
  resolver: PublicKeyResolver;
  tierResolver?: AssuranceTierResolver;
  webauthnCredentialResolver?: WebAuthnCredentialResolver;
  liveBinding: ApprovalRequestBinding;
  isNonceBurned: (jti: string) => boolean;
  nowMs?: number;
  assuranceFloor: AssuranceTier;
}): VerifyApprovalTokenResult {
  const { token } = options;
  if (
    !token ||
    token.approval_token_schema !== "ucase-approval-token-v1" ||
    typeof token.jti !== "string" ||
    token.jti.length === 0 ||
    !token.binding ||
    typeof token.decision !== "string"
  ) {
    return { ok: false, code: "MALFORMED_TOKEN", message: "approval token is malformed" };
  }

  // 1) Signature + key/credential: ed25519 reuses verifyEvent; WebAuthn verifies
  // the authenticator assertion against the pinned credential and live binding.
  const signatureAlg = (token.signature as { alg?: unknown } | undefined)?.alg;
  let signatureKeyId: string;
  let maxTier: AssuranceTier;
  let tier: AssuranceTier;
  if (signatureAlg === "webauthn") {
    const assertion = verifyWebAuthnAssertion({
      token,
      credentialResolver: options.webauthnCredentialResolver,
      liveBinding: options.liveBinding
    });
    if (!assertion.ok) {
      return { ok: false, code: assertion.code, message: assertion.message };
    }
    const claimed = claimedWebAuthnAssuranceTier(token);
    if (!claimed.ok) {
      return { ok: false, code: "MALFORMED_TOKEN", message: claimed.message };
    }
    signatureKeyId = assertion.key_id;
    maxTier = normalizeAssuranceTier(assertion.maxTier);
    tier = claimed.tier;
  } else {
    const signatureResult = verifyEvent(token as unknown as Record<string, unknown>, options.resolver);
    if (!signatureResult.ok) {
      return { ok: false, code: signatureResult.code, message: signatureResult.message };
    }
    signatureKeyId = signatureResult.key_id;
    // The keyring supplies only the key's MAX cap. New tokens carry the signed
    // method + claimed tier; legacy tokens with no method retain the old
    // behavior by claiming the key cap. A tier resolver that cannot place the
    // key fails closed at untrusted_automation.
    maxTier = normalizeAssuranceTier(options.tierResolver?.(signatureResult.key_id, token.created_at));
    const claimed = claimedAssuranceTier(token, maxTier);
    if (!claimed.ok) {
      return { ok: false, code: "MALFORMED_TOKEN", message: claimed.message };
    }
    tier = claimed.tier;
  }

  // 2) Binding: every bound field must equal the LIVE run's recomputed value.
  for (const field of BINDING_FIELDS) {
    if (token.binding[field] !== options.liveBinding[field]) {
      return {
        ok: false,
        code: "BINDING_MISMATCH",
        message: `approval token binding.${field} does not match the live run`
      };
    }
  }

  // 3) Expiry: exp must not have passed.
  const now = options.nowMs ?? Date.now();
  const exp = Date.parse(token.exp);
  if (Number.isNaN(exp) || now > exp) {
    return { ok: false, code: "TOKEN_EXPIRED", message: "approval token has expired" };
  }

  // 4) Single-use: the nonce must be unburned.
  if (options.isNonceBurned(token.jti)) {
    return { ok: false, code: "NONCE_BURNED", message: "approval token nonce already burned (replay)" };
  }

  // 5) Assurance tier cap + policy floor. WebAuthn reaches this point with a
  // cryptographically proven hardware tier; ed25519 reaches it with a signed
  // method claim. Both are capped by the pinned keyring entry and then compared
  // with the policy floor.
  if (!tierMeetsFloor(maxTier, tier)) {
    return {
      ok: false,
      code: "ASSURANCE_OVER_CLAIM",
      message: `approval token claims assurance tier ${tier} above key ${signatureKeyId} cap ${maxTier}`
    };
  }
  if (!tierMeetsFloor(tier, options.assuranceFloor)) {
    return {
      ok: false,
      code: "ASSURANCE_TOO_LOW",
      message: `approval token assurance tier ${tier} does not meet floor ${options.assuranceFloor}`
    };
  }

  return {
    ok: true,
    jti: token.jti,
    decision: token.decision as ApprovalDecision,
    key_id: signatureKeyId,
    assurance_tier: tier
  };
}
