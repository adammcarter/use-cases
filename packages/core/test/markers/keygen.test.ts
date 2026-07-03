import { createPrivateKey, createPublicKey } from "node:crypto";
import { describe, expect, test } from "vitest";
import { generateSigningKeypair } from "../../src/markers/keygen.js";
import { signEvent, singleKeyResolver, verifyEvent } from "../../src/markers/index.js";

// Task 3 (0.1.0): `uc keygen` mints an ed25519 keypair in exactly the PEM
// formats `prove`/`--public-key` already consume — PKCS8 private, SPKI public.
describe("generateSigningKeypair (opt-in signed tier)", () => {
  test("returns PKCS8 private + SPKI public PEM that node:crypto accepts", () => {
    const { privatePem, publicPem } = generateSigningKeypair();

    expect(privatePem).toMatch(/^-----BEGIN PRIVATE KEY-----/);
    expect(privatePem.trimEnd()).toMatch(/-----END PRIVATE KEY-----$/);
    expect(publicPem).toMatch(/^-----BEGIN PUBLIC KEY-----/);
    expect(publicPem.trimEnd()).toMatch(/-----END PUBLIC KEY-----$/);

    // Both PEMs load without throwing (the same calls markers.ts makes).
    const privateKey = createPrivateKey(privatePem);
    const publicKey = createPublicKey(publicPem);
    expect(privateKey.asymmetricKeyType).toBe("ed25519");
    expect(publicKey.asymmetricKeyType).toBe("ed25519");
  });

  test("a sign/verify round-trip through proofSignature.ts passes", () => {
    const { privatePem, publicPem } = generateSigningKeypair();
    const keyId = "ci-key-1";

    const unsignedEvent = { kind: "proof", row_id: "row.a", created_at: "2026-07-03T00:00:00Z" };
    const signed = signEvent(unsignedEvent, createPrivateKey(privatePem), keyId);

    const resolver = singleKeyResolver(createPublicKey(publicPem));
    const result = verifyEvent(signed, resolver);
    expect(result.ok).toBe(true);
  });

  test("each call yields a fresh, distinct keypair", () => {
    const a = generateSigningKeypair();
    const b = generateSigningKeypair();
    expect(a.privatePem).not.toBe(b.privatePem);
    expect(a.publicPem).not.toBe(b.publicPem);
  });
});
