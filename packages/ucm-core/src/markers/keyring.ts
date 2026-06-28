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

export const KEYRING_SCHEMA_ID = "https://use-case-matrix.dev/schemas/v1/keyring.schema.json";

export interface KeyringKey {
  key_id: string;
  algorithm: "ed25519";
  public_key: string; // PEM-encoded ed25519 public key
  valid_from: string; // ISO-8601 timestamp
  valid_until: string | null; // ISO-8601 timestamp, or null for open-ended
  status: "active" | "revoked";
}

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

// Build a fail-closed resolver over a keyring. A key_id resolves to its PEM only
// when the key is active and the proof's createdAt is within its window.
export function keyringResolver(keyring: Keyring): PublicKeyResolver {
  const byId = new Map<string, KeyringKey>();
  for (const key of keyring.keys) {
    // First entry per key_id wins; later duplicates are ignored.
    if (!byId.has(key.key_id)) {
      byId.set(key.key_id, key);
    }
  }
  return (keyId: string, createdAt?: string) => {
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
    return key.public_key;
  };
}

// Convenience used by the CLI: load a keyring file and build its resolver.
export function keyringPublicKeyResolverFromFile(filePath: string): PublicKeyResolver {
  return keyringResolver(loadKeyring(filePath));
}
