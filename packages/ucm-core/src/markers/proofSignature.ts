// ed25519 signing + verification for trusted-CI proof events (spec 5.2/5.3,
// amendment 3).
//
// The signing payload is `canonical_json(event without the signature field)`
// (spec 5.3). The private signing key exists only in trusted CI; the public
// verification key lives in the repo/config. ed25519 is used through node:crypto
// with a null algorithm: `crypto.sign(null, data, privateKey)` and
// `crypto.verify(null, data, publicKey, signature)`. Everything here is pure
// crypto over in-memory values; no filesystem or git access.
import { sign, verify, type KeyObject } from "node:crypto";
import { canonicalJson } from "./canonicalJson.js";

// The signature block embedded in a proof event (spec 5.2).
export interface ProofSignatureBlock {
  alg: "ed25519";
  key_id: string;
  value: string; // base64-encoded ed25519 signature
}

// A key (PEM string or a node KeyObject). PEM is the on-disk form per spec.
export type PemOrKeyObject = string | KeyObject;

// Maps a signature key_id to its public key. Returning undefined means the
// key_id is unknown -> the event is INVALID (spec 5.3 rule 2).
export type PublicKeyResolver = (keyId: string) => PemOrKeyObject | undefined;

// Stable reasons a signature can fail verification. These line up 1:1 with the
// signature-related EvidenceErrorCode values so the ledger can forward them.
export const SignatureFailureCode = Object.freeze({
  SIGNATURE_MISSING: "SIGNATURE_MISSING",
  SIGNATURE_ALG_UNSUPPORTED: "SIGNATURE_ALG_UNSUPPORTED",
  UNKNOWN_KEY_ID: "UNKNOWN_KEY_ID",
  BAD_SIGNATURE: "BAD_SIGNATURE"
} as const);

export type SignatureFailureCode =
  (typeof SignatureFailureCode)[keyof typeof SignatureFailureCode];

export type VerifyEventResult =
  | { ok: true; key_id: string }
  | { ok: false; code: SignatureFailureCode; message: string };

// Drop the `signature` field (if any) from a shallow copy of an event.
function stripSignature<T extends Record<string, unknown>>(
  event: T
): Omit<T, "signature"> {
  const rest: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(event)) {
    if (key !== "signature") {
      rest[key] = value;
    }
  }
  return rest as Omit<T, "signature">;
}

// The canonical signing payload: canonical_json(event without signature)
// (spec 5.3). Defensive: any embedded signature is removed before canonicalizing
// so signing and verifying always agree on the payload.
export function proofSigningPayload(event: Record<string, unknown>): string {
  return canonicalJson(stripSignature(event));
}

// Sign an unsigned proof event with an ed25519 private key, returning the event
// with its `signature` block attached. The caller passes the event WITHOUT a
// signature; any pre-existing signature field is ignored and replaced.
//
// node:crypto call: sign(null, data, privateKey) -> Buffer (ed25519).
export function signEvent<T extends Record<string, unknown>>(
  eventWithoutSignature: T,
  privateKey: PemOrKeyObject,
  keyId: string
): Omit<T, "signature"> & { signature: ProofSignatureBlock } {
  const payload = proofSigningPayload(eventWithoutSignature);
  const value = sign(null, Buffer.from(payload, "utf8"), privateKey).toString("base64");
  return {
    ...stripSignature(eventWithoutSignature),
    signature: { alg: "ed25519", key_id: keyId, value }
  };
}

// Verify a proof event's ed25519 signature against the public key resolved from
// its key_id (spec 5.3). Returns ok, or a precise failure reason:
//   SIGNATURE_MISSING          - no signature block / missing fields (rule 1)
//   SIGNATURE_ALG_UNSUPPORTED  - alg is not "ed25519"
//   UNKNOWN_KEY_ID             - resolver has no key for key_id (rule 2)
//   BAD_SIGNATURE              - signature does not verify (rule 3)
//
// node:crypto call: verify(null, data, publicKey, signature) -> boolean.
export function verifyEvent(
  event: Record<string, unknown>,
  resolver: PublicKeyResolver
): VerifyEventResult {
  const signature = event.signature as Partial<ProofSignatureBlock> | undefined;
  if (
    !signature ||
    typeof signature !== "object" ||
    typeof signature.key_id !== "string" ||
    typeof signature.value !== "string"
  ) {
    return {
      ok: false,
      code: SignatureFailureCode.SIGNATURE_MISSING,
      message: "proof event has no usable signature block (unsigned events are invalid)"
    };
  }
  if (signature.alg !== "ed25519") {
    return {
      ok: false,
      code: SignatureFailureCode.SIGNATURE_ALG_UNSUPPORTED,
      message: `unsupported signature alg: ${String(signature.alg)} (only ed25519 is allowed)`
    };
  }
  const publicKey = resolver(signature.key_id);
  if (publicKey === undefined) {
    return {
      ok: false,
      code: SignatureFailureCode.UNKNOWN_KEY_ID,
      message: `unknown signature key_id: ${signature.key_id}`
    };
  }
  const payload = proofSigningPayload(event);
  let verified = false;
  try {
    verified = verify(
      null,
      Buffer.from(payload, "utf8"),
      publicKey,
      Buffer.from(signature.value, "base64")
    );
  } catch {
    // A malformed key or signature surfaces as a bad signature, not a throw.
    verified = false;
  }
  if (!verified) {
    return {
      ok: false,
      code: SignatureFailureCode.BAD_SIGNATURE,
      message: `signature for key_id ${signature.key_id} did not verify`
    };
  }
  return { ok: true, key_id: signature.key_id };
}
