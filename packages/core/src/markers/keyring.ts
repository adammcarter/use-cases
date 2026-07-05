// Multi-key public-key registry (keyring) for verifying trusted-CI proof-event
// signatures (schemas/v1/keyring.schema.json).
//
// This is the OPT-IN alternative to the single `--public-key` path. Where
// singleKeyResolver trusts one explicitly-provided key unconditionally, a
// keyring carries several keys, each with a validity window and a revocation
// status, so keys can be rotated and retired without changing code.
//
// Resolution is FAIL-CLOSED: a key_id resolves to a public key ONLY when the
// key exists, its status is "active", and the proof's created_at falls inside
// [valid_from, valid_until] (valid_until null = open-ended). A revoked, unknown,
// or out-of-window key_id resolves to undefined, so verifyEvent reports
// UNKNOWN_KEY_ID and the proof does not verify.
import { readFileSync } from "node:fs";
import { validateBySchemaId } from "../schema/index.js";
import type { PublicKeyResolver } from "./proofSignature.js";

export const KEYRING_SCHEMA_ID = "https://use-cases.dev/schemas/v1/keyring.schema.json";

export type KeyringAssuranceTier =
  | "untrusted_automation"
  | "same_channel_operator_confirmation"
  | "trusted_host_user_presence"
  | "webauthn_hardware";

export type WebAuthnPublicKeyAlg = -7 | -8;

interface KeyringKeyBase {
  valid_from: string; // ISO-8601 timestamp
  valid_until: string | null; // ISO-8601 timestamp, or null for open-ended
  status: "active" | "revoked";
  // F3: human-approval assurance tier CAP bound to the key by the keyring
  // curator. The signed token claims the actual method/tier; this value is only
  // the highest tier this key may assert. Absent => untrusted_automation.
  max_assurance_tier?: KeyringAssuranceTier;
  // Legacy alias accepted for old keyrings. New keyrings should use
  // max_assurance_tier; when both are present, max_assurance_tier wins.
  assurance_tier?: KeyringAssuranceTier;
}

export interface Ed25519KeyringKey extends KeyringKeyBase {
  key_id: string;
  algorithm: "ed25519";
  public_key: string; // PEM-encoded ed25519 public key
}

export interface WebAuthnKeyringCredential extends KeyringKeyBase {
  algorithm: "webauthn";
  credential_id: string; // base64url WebAuthn credential id
  credential_public_key_alg: WebAuthnPublicKeyAlg; // COSE alg: ES256=-7, EdDSA=-8
  // Base64url DER SPKI public key. This is the node:crypto-verifiable
  // equivalent of the authenticator's COSE credential public key.
  credential_public_key_spki: string;
  max_assurance_tier?: KeyringAssuranceTier;
}

export type KeyringKey = Ed25519KeyringKey | WebAuthnKeyringCredential;

export interface WebAuthnCredential {
  credential_id: string;
  credential_public_key_alg: WebAuthnPublicKeyAlg;
  credential_public_key_spki: string;
  max_assurance_tier: KeyringAssuranceTier;
}

// F3: resolve a key_id to the maximum assurance tier the KEYRING lets it assert,
// but ONLY when the key is active and in-window at `createdAt` (same fail-closed
// gate as the public-key resolver). A key that would not verify a signature must
// never lend its cap either. Returns undefined when the key does not resolve.
export type MaxAssuranceTierResolver = (
  keyId: string,
  createdAt?: string
) => KeyringAssuranceTier | undefined;

export type AssuranceTierResolver = MaxAssuranceTierResolver;

export type WebAuthnCredentialResolver = (
  credentialId: string,
  createdAt?: string
) => WebAuthnCredential | undefined;

export interface Keyring {
  keyring_schema_id: "ucase-public-key-registry-v1";
  keys: KeyringKey[];
}

// A loader/validator error carrying a stable `code` so callers can branch.
export class KeyringError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "KeyringError";
    this.code = code;
  }
}

// Parse + schema-validate a keyring object. Throws KeyringError on any failure.
export function parseKeyring(value: unknown, sourcePath: string | null = null): Keyring {
  const result = validateBySchemaId(KEYRING_SCHEMA_ID, value, sourcePath);
  if (!result.ok) {
    const details = result.diagnostics.map((d) => `${d.json_pointer ?? ""} ${d.message}`.trim()).join("; ");
    throw new KeyringError("keyring_schema_invalid", `keyring file is not a valid keyring: ${details}`);
  }
  return value as Keyring;
}

// Read, JSON-parse, and schema-validate a keyring file from disk.
export function loadKeyring(filePath: string): Keyring {
  let text: string;
  try {
    text = readFileSync(filePath, "utf8");
  } catch (error) {
    throw new KeyringError(
      "keyring_unreadable",
      `could not read keyring file ${filePath}: ${error instanceof Error ? error.message : String(error)}`
    );
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (error) {
    throw new KeyringError(
      "keyring_invalid_json",
      `keyring file ${filePath} is not valid JSON: ${error instanceof Error ? error.message : String(error)}`
    );
  }
  return parseKeyring(value, filePath);
}

function keyIndex(keyring: Keyring): Map<string, Ed25519KeyringKey> {
  const byId = new Map<string, Ed25519KeyringKey>();
  for (const key of keyring.keys) {
    // First entry per key_id wins; later duplicates are ignored.
    if (key.algorithm === "ed25519" && !byId.has(key.key_id)) {
      byId.set(key.key_id, key);
    }
  }
  return byId;
}

function credentialIndex(keyring: Keyring): Map<string, WebAuthnKeyringCredential> {
  const byId = new Map<string, WebAuthnKeyringCredential>();
  for (const key of keyring.keys) {
    // First entry per credential_id wins; later duplicates are ignored.
    if (key.algorithm === "webauthn" && !byId.has(key.credential_id)) {
      byId.set(key.credential_id, key);
    }
  }
  return byId;
}

// Fail-closed gate shared by the public-key and assurance-tier resolvers: return
// the key ONLY when it exists, is active, and createdAt is inside its window.
function resolveActiveInWindowKey<T extends KeyringKeyBase>(
  byId: Map<string, T>,
  keyId: string,
  createdAt?: string
): T | undefined {
  const key = byId.get(keyId);
  if (!key || key.status !== "active") {
    return undefined; // unknown or revoked -> fail closed
  }
  // Without a created_at we cannot prove the window holds -> fail closed.
  if (createdAt === undefined) {
    return undefined;
  }
  const at = Date.parse(createdAt);
  if (Number.isNaN(at)) {
    return undefined;
  }
  const from = Date.parse(key.valid_from);
  if (Number.isNaN(from) || at < from) {
    return undefined;
  }
  if (key.valid_until !== null) {
    const until = Date.parse(key.valid_until);
    if (Number.isNaN(until) || at > until) {
      return undefined;
    }
  }
  return key;
}

// Build a fail-closed resolver over a keyring. A key_id resolves to its PEM only
// when the key is active and the proof's createdAt is within its window.
export function keyringResolver(keyring: Keyring): PublicKeyResolver {
  const byId = keyIndex(keyring);
  return (keyId: string, createdAt?: string) =>
    resolveActiveInWindowKey(byId, keyId, createdAt)?.public_key;
}

function keyMaxAssuranceTier(key: KeyringKeyBase): KeyringAssuranceTier {
  return key.max_assurance_tier ?? key.assurance_tier ?? "untrusted_automation";
}

// F3: build a fail-closed max-assurance-tier resolver over the SAME keyring. It
// gates identically to keyringResolver, then returns the key's cap
// (defaulting an absent tier to untrusted_automation — never trust by omission).
export function keyringMaxAssuranceTierResolver(keyring: Keyring): MaxAssuranceTierResolver {
  const byId = keyIndex(keyring);
  return (keyId: string, createdAt?: string) => {
    const key = resolveActiveInWindowKey(byId, keyId, createdAt);
    if (!key) {
      return undefined;
    }
    const tier = keyMaxAssuranceTier(key);
    // WebAuthn hardware assurance is cryptographically proven by an
    // authenticator assertion, never by an ed25519 signer/keyring cap.
    return tier === "webauthn_hardware" ? "untrusted_automation" : tier;
  };
}

export const keyringAssuranceTierResolver = keyringMaxAssuranceTierResolver;

// Build a fail-closed WebAuthn credential resolver over a keyring. A
// credential_id resolves only when it is pinned in this keyring, active, and
// in-window at the token's created_at.
export function keyringWebAuthnCredentialResolver(keyring: Keyring): WebAuthnCredentialResolver {
  const byCredentialId = credentialIndex(keyring);
  return (credentialId: string, createdAt?: string) => {
    const credential = resolveActiveInWindowKey(byCredentialId, credentialId, createdAt);
    if (!credential) {
      return undefined;
    }
    if (credential.credential_public_key_alg !== -7 && credential.credential_public_key_alg !== -8) {
      return undefined;
    }
    return {
      credential_id: credential.credential_id,
      credential_public_key_alg: credential.credential_public_key_alg,
      credential_public_key_spki: credential.credential_public_key_spki,
      max_assurance_tier: keyMaxAssuranceTier(credential)
    };
  };
}

// Convenience used by the CLI: load a keyring file and build its resolver.
export function keyringPublicKeyResolverFromFile(filePath: string): PublicKeyResolver {
  return keyringResolver(loadKeyring(filePath));
}
