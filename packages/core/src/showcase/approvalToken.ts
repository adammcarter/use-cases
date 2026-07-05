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
import { randomUUID } from "node:crypto";
import {
  signEvent,
  verifyEvent,
  type PemOrKeyObject,
  type ProofSignatureBlock,
  type PublicKeyResolver
} from "../markers/proofSignature.js";
import type { AssuranceTierResolver } from "../markers/keyring.js";
import {
  assuranceTierForMethod,
  isAssuranceMethod,
  isAssuranceTier,
  normalizeAssuranceTier,
  tierMeetsFloor,
  type AssuranceMethod,
  type AssuranceTier
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
  signature: ProofSignatureBlock;
}

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

// Plugin-side VERIFY: the whole gate. Order is deliberate — signature/key first
// (so a tampered payload or an unknown key surfaces as a crypto failure), then
// the independent binding / expiry / single-use / assurance-tier checks.
export function verifyApprovalToken(options: {
  token: ApprovalToken;
  resolver: PublicKeyResolver;
  tierResolver?: AssuranceTierResolver;
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

  // 1) Signature + key: reuses verifyEvent + the fail-closed keyring VERBATIM.
  const signatureResult = verifyEvent(token as unknown as Record<string, unknown>, options.resolver);
  if (!signatureResult.ok) {
    return { ok: false, code: signatureResult.code, message: signatureResult.message };
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

  // 5) Assurance tier: the keyring supplies only the key's MAX cap. New tokens
  // carry the signed method + claimed tier; legacy tokens with no method retain
  // the old behavior by claiming the key cap. A tier resolver that cannot place
  // the key fails closed at untrusted_automation.
  const maxTier = normalizeAssuranceTier(options.tierResolver?.(signatureResult.key_id, token.created_at));
  const claimed = claimedAssuranceTier(token, maxTier);
  if (!claimed.ok) {
    return { ok: false, code: "MALFORMED_TOKEN", message: claimed.message };
  }
  const tier = claimed.tier;
  if (!tierMeetsFloor(maxTier, tier)) {
    return {
      ok: false,
      code: "ASSURANCE_OVER_CLAIM",
      message: `approval token claims assurance tier ${tier} above key ${signatureResult.key_id} cap ${maxTier}`
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
    key_id: signatureResult.key_id,
    assurance_tier: tier
  };
}
