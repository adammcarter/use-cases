import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  keyringResolver,
  keyringPublicKeyResolverFromFile,
  loadKeyring,
  signEvent,
  singleKeyResolver,
  verifyEvent,
  type Keyring
} from "../../src/markers/index.js";

// Two independent ed25519 keypairs: key A is the "current" CI signer, key B is
// the rotated-in successor. The keyring trusts both via distinct key_ids.
function ed25519Pem(): { publicKeyPem: string; privateKeyPem: string } {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString()
  };
}

const KEY_A = ed25519Pem();
const KEY_B = ed25519Pem();

// A minimal proof-event-shaped object: verifyEvent only needs a signature block
// plus a stable payload (created_at threads to the resolver's validity window).
function unsignedEvent(createdAt: string): Record<string, unknown> {
  return {
    schema: "ucase-proof-event-v1",
    event_id: "01JABCDEFAAAAAAAAAAAAAAAAAA",
    created_at: createdAt,
    row: { row_id: "checkout.apply_coupon" }
  };
}

function signedBy(keyPem: string, keyId: string, createdAt: string): Record<string, unknown> {
  return signEvent(unsignedEvent(createdAt), keyPem, keyId) as Record<string, unknown>;
}

// A keyring with one active in-window key (ci-key-1 -> A), one revoked key
// (ci-key-0 -> B with an expired window), unless overridden.
function keyringObject(overrides: Partial<Keyring> = {}): Keyring {
  return {
    keyring_schema_id: "ucase-public-key-registry-v1",
    keys: [
      {
        key_id: "ci-key-1",
        algorithm: "ed25519",
        public_key: KEY_A.publicKeyPem,
        valid_from: "2026-01-01T00:00:00Z",
        valid_until: null,
        status: "active"
      },
      {
        key_id: "ci-key-0",
        algorithm: "ed25519",
        public_key: KEY_B.publicKeyPem,
        valid_from: "2025-01-01T00:00:00Z",
        valid_until: "2026-01-01T00:00:00Z",
        status: "revoked"
      }
    ],
    ...overrides
  };
}

const IN_WINDOW = "2026-06-28T12:05:00Z";

describe("keyringResolver: status + validity window enforcement", () => {
  test("an active, in-window key verifies the proof it signed", () => {
    const resolver = keyringResolver(keyringObject());
    const event = signedBy(KEY_A.privateKeyPem, "ci-key-1", IN_WINDOW);
    expect(verifyEvent(event, resolver).ok).toBe(true);
  });

  test("a revoked key does NOT resolve (proof does not verify)", () => {
    const resolver = keyringResolver(keyringObject());
    // Signed with key B inside its window, but its keyring entry is revoked.
    const event = signedBy(KEY_B.privateKeyPem, "ci-key-0", "2025-06-01T00:00:00Z");
    const result = verifyEvent(event, resolver);
    expect(result.ok).toBe(false);
    expect(result.ok === false && result.code).toBe("UNKNOWN_KEY_ID");
  });

  test("an unknown key_id does NOT resolve", () => {
    const resolver = keyringResolver(keyringObject());
    const event = signedBy(KEY_A.privateKeyPem, "ci-key-does-not-exist", IN_WINDOW);
    expect(verifyEvent(event, resolver).ok).toBe(false);
  });

  test("a key whose valid_until is before the proof created_at does NOT resolve", () => {
    const resolver = keyringResolver(
      keyringObject({
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: KEY_A.publicKeyPem,
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: "2026-03-01T00:00:00Z",
            status: "active"
          }
        ]
      })
    );
    // created_at (June) is after valid_until (March).
    const event = signedBy(KEY_A.privateKeyPem, "ci-key-1", IN_WINDOW);
    expect(verifyEvent(event, resolver).ok).toBe(false);
  });

  test("a key whose valid_from is after the proof created_at does NOT resolve", () => {
    const resolver = keyringResolver(
      keyringObject({
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: KEY_A.publicKeyPem,
            valid_from: "2026-12-01T00:00:00Z",
            valid_until: null,
            status: "active"
          }
        ]
      })
    );
    // created_at (June) is before valid_from (December).
    const event = signedBy(KEY_A.privateKeyPem, "ci-key-1", IN_WINDOW);
    expect(verifyEvent(event, resolver).ok).toBe(false);
  });

  test("rotation: a proof signed by EITHER active key verifies", () => {
    const resolver = keyringResolver(
      keyringObject({
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: KEY_A.publicKeyPem,
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: null,
            status: "active"
          },
          {
            key_id: "ci-key-2",
            algorithm: "ed25519",
            public_key: KEY_B.publicKeyPem,
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: null,
            status: "active"
          }
        ]
      })
    );
    const eventA = signedBy(KEY_A.privateKeyPem, "ci-key-1", IN_WINDOW);
    const eventB = signedBy(KEY_B.privateKeyPem, "ci-key-2", IN_WINDOW);
    expect(verifyEvent(eventA, resolver).ok).toBe(true);
    expect(verifyEvent(eventB, resolver).ok).toBe(true);
  });

  test("the active boundary timestamps (valid_from / valid_until) are inclusive", () => {
    const resolver = keyringResolver(
      keyringObject({
        keys: [
          {
            key_id: "ci-key-1",
            algorithm: "ed25519",
            public_key: KEY_A.publicKeyPem,
            valid_from: "2026-01-01T00:00:00Z",
            valid_until: "2026-12-31T23:59:59Z",
            status: "active"
          }
        ]
      })
    );
    const atStart = signedBy(KEY_A.privateKeyPem, "ci-key-1", "2026-01-01T00:00:00Z");
    const atEnd = signedBy(KEY_A.privateKeyPem, "ci-key-1", "2026-12-31T23:59:59Z");
    expect(verifyEvent(atStart, resolver).ok).toBe(true);
    expect(verifyEvent(atEnd, resolver).ok).toBe(true);
  });
});

describe("loadKeyring + keyringPublicKeyResolverFromFile (file loading)", () => {
  let dir: string;

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), "ucp-keyring-"));
  });

  afterAll(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  test("loads a valid keyring file and resolves an active in-window key", () => {
    const path = join(dir, "valid.json");
    writeFileSync(path, JSON.stringify(keyringObject()), "utf8");
    const resolver = keyringPublicKeyResolverFromFile(path);
    const event = signedBy(KEY_A.privateKeyPem, "ci-key-1", IN_WINDOW);
    expect(verifyEvent(event, resolver).ok).toBe(true);
  });

  test("a malformed (non-JSON) keyring file throws a clear error", () => {
    const path = join(dir, "garbage.json");
    writeFileSync(path, "this is not json {", "utf8");
    expect(() => loadKeyring(path)).toThrowError(/keyring/i);
  });

  test("a schema-invalid keyring file throws a clear error", () => {
    const path = join(dir, "schema-bad.json");
    // Missing required status/algorithm fields and wrong schema id.
    writeFileSync(
      path,
      JSON.stringify({ keyring_schema_id: "wrong-id", keys: [{ key_id: "x" }] }),
      "utf8"
    );
    expect(() => loadKeyring(path)).toThrowError(/keyring/i);
  });

  test("a missing keyring file throws a clear error", () => {
    expect(() => loadKeyring(join(dir, "does-not-exist.json"))).toThrowError(/keyring/i);
  });
});

describe("singleKeyResolver is unchanged: no window/status enforcement", () => {
  test("a single explicitly-provided key is trusted regardless of createdAt", () => {
    const resolver = singleKeyResolver(KEY_A.publicKeyPem);
    // Even a far-future created_at still resolves: single-key path trusts the key.
    const event = signedBy(KEY_A.privateKeyPem, "any-key-id", "2099-01-01T00:00:00Z");
    expect(verifyEvent(event, resolver).ok).toBe(true);
  });
});
