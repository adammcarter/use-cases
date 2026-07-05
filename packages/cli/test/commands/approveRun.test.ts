// F3 — `uc approve-run` is the OUT-OF-BAND human signer. It runs in the human's
// OWN shell with an ed25519 key that lives OUTSIDE the in-session agent's
// granted scope, and turns a plugin-minted ApprovalRequest into a signed
// approval token. The plugin later verifies that token.
//
// KEY CUSTODY is the whole guarantee: a signer with NO access to the key cannot
// mint a token. This suite proves the signer round-trips with a key AND fails
// closed without one.
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { approveRunCommand } from "../../src/commands/approveRun.js";
import {
  keyringAssuranceTierResolver,
  keyringWebAuthnCredentialResolver,
  keyringResolver,
  mintApprovalRequest,
  verifyApprovalToken,
  type ApprovalRequestBinding,
  type ApprovalRequest,
  type ApprovalToken,
  type Keyring
} from "@adammcarter/use-cases-core";
import { canonicalJson } from "../../../core/src/markers/canonicalJson.js";

let dir: string;

const KEY = (() => {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKeyPem: privateKey.export({ type: "pkcs8", format: "pem" }).toString()
  };
})();

const KEYRING: Keyring = {
  keyring_schema_id: "ucase-public-key-registry-v1",
  keys: [
    {
      key_id: "human-key-1",
      algorithm: "ed25519",
      public_key: KEY.publicKeyPem,
      valid_from: "2026-01-01T00:00:00Z",
      valid_until: null,
      status: "active",
      max_assurance_tier: "trusted_host_user_presence"
    }
  ]
};

const AT = Date.parse("2026-06-28T12:05:00.000Z");

const WEBAUTHN_CREDENTIAL = (() => {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    credentialId: "approve-run-webauthn-ed25519",
    publicKeySpki: publicKey.export({ type: "spki", format: "der" }).toString("base64url"),
    privateKey
  };
})();

const WEBAUTHN_KEYRING: Keyring = {
  keyring_schema_id: "ucase-public-key-registry-v1",
  keys: [
    {
      algorithm: "webauthn",
      credential_id: WEBAUTHN_CREDENTIAL.credentialId,
      credential_public_key_alg: -8,
      credential_public_key_spki: WEBAUTHN_CREDENTIAL.publicKeySpki,
      valid_from: "2026-01-01T00:00:00Z",
      valid_until: null,
      status: "active",
      max_assurance_tier: "webauthn_hardware"
    }
  ]
};

function binding(): ApprovalRequestBinding {
  return {
    run_id: "run.alpha",
    finish_event_id: "evt.run.alpha.7",
    plan_content_hash: "sha256:plan",
    ledger_head_hash: "sha256:head",
    evidence_digest: "sha256:ev",
    git_commit: "0123456789abcdef0123456789abcdef01234567",
    ci_freshness_digest: "sha256:ci"
  };
}

function writeRequest(): string {
  const request = mintApprovalRequest({ binding: binding(), nowMs: AT, ttlMinutes: 15 });
  const path = join(dir, "request.json");
  writeFileSync(path, JSON.stringify(request), "utf8");
  return path;
}

function writeWebAuthnAssertion(request: ApprovalRequest): string {
  const clientDataJson = Buffer.from(
    JSON.stringify({
      type: "webauthn.get",
      challenge: createHash("sha256").update(canonicalJson(request.binding)).digest().toString("base64url"),
      origin: "https://use-cases.dev"
    }),
    "utf8"
  );
  const authenticatorData = Buffer.concat([
    createHash("sha256").update("use-cases.dev").digest(),
    Buffer.from([0x05]),
    Buffer.from([0, 0, 0, 1])
  ]);
  const signatureBase = Buffer.concat([
    authenticatorData,
    createHash("sha256").update(clientDataJson).digest()
  ]);
  const assertionPath = join(dir, "webauthn-assertion.json");
  writeFileSync(
    assertionPath,
    JSON.stringify({
      credential_id: WEBAUTHN_CREDENTIAL.credentialId,
      authenticator_data: authenticatorData.toString("base64url"),
      client_data_json: clientDataJson.toString("base64url"),
      signature: sign(null, signatureBase, WEBAUTHN_CREDENTIAL.privateKey).toString("base64url")
    }),
    "utf8"
  );
  return assertionPath;
}

function extractToken(envelope: unknown): ApprovalToken {
  const token = (envelope as { data?: { approval_token?: ApprovalToken } }).data?.approval_token;
  if (!token) {
    throw new Error(`no approval_token in envelope: ${JSON.stringify(envelope)}`);
  }
  return token;
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "ucm-approve-run-"));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  delete process.env.UCM_TEST_APPROVAL_KEY;
});

describe("uc approve-run — out-of-band human signer", () => {
  test("(j/l) with a key FILE, signs a token the plugin then verifies against the keyring", () => {
    const requestPath = writeRequest();
    const keyPath = join(dir, "human.key");
    writeFileSync(keyPath, KEY.privateKeyPem, { mode: 0o600 });

    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: {
        request: requestPath,
        keyFile: keyPath,
        keyId: "human-key-1",
        decision: "approved"
      }
    });
    expect(result.exitCode).toBe(0);
    const token = extractToken(result.envelope);

    const verification = verifyApprovalToken({
      token,
      resolver: keyringResolver(KEYRING),
      tierResolver: keyringAssuranceTierResolver(KEYRING),
      liveBinding: binding(),
      isNonceBurned: () => false,
      nowMs: AT,
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(verification.ok).toBe(true);
    expect(verification.ok === true && verification.decision).toBe("approved");
  });

  test("with a key from an ENV var, signs a verifiable token", () => {
    const requestPath = writeRequest();
    process.env.UCM_TEST_APPROVAL_KEY = KEY.privateKeyPem;
    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: { request: requestPath, keyEnv: "UCM_TEST_APPROVAL_KEY", keyId: "human-key-1", decision: "approved_with_known_gaps" }
    });
    expect(result.exitCode).toBe(0);
    const token = extractToken(result.envelope);
    expect(token.decision).toBe("approved_with_known_gaps");
    const verification = verifyApprovalToken({
      token,
      resolver: keyringResolver(KEYRING),
      tierResolver: keyringAssuranceTierResolver(KEYRING),
      liveBinding: binding(),
      isNonceBurned: () => false,
      nowMs: AT,
      assuranceFloor: "trusted_host_user_presence"
    });
    expect(verification.ok).toBe(true);
  });

  test("--out writes the token to a file", () => {
    const requestPath = writeRequest();
    const keyPath = join(dir, "human.key");
    writeFileSync(keyPath, KEY.privateKeyPem, { mode: 0o600 });
    const outPath = join(dir, "token.json");
    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: { request: requestPath, keyFile: keyPath, keyId: "human-key-1", out: outPath }
    });
    expect(result.exitCode).toBe(0);
    const token = JSON.parse(readFileSync(outPath, "utf8")) as ApprovalToken;
    expect(token.approval_token_schema).toBe("ucase-approval-token-v1");
    expect(token.signature.alg).toBe("ed25519");
  });

  test("--webauthn-assertion builds a verifiable WebAuthn token without a private key", () => {
    const request = mintApprovalRequest({ binding: binding(), nowMs: AT, ttlMinutes: 15 });
    const requestPath = join(dir, "request.json");
    writeFileSync(requestPath, JSON.stringify(request), "utf8");
    const assertionPath = writeWebAuthnAssertion(request);

    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: {
        request: requestPath,
        webauthnAssertion: assertionPath,
        decision: "approved"
      }
    });
    expect(result.exitCode).toBe(0);
    const token = extractToken(result.envelope);
    expect(token.signature.alg).toBe("webauthn");

    const verification = verifyApprovalToken({
      token,
      resolver: keyringResolver(WEBAUTHN_KEYRING),
      tierResolver: keyringAssuranceTierResolver(WEBAUTHN_KEYRING),
      webauthnCredentialResolver: keyringWebAuthnCredentialResolver(WEBAUTHN_KEYRING),
      liveBinding: binding(),
      isNonceBurned: () => false,
      nowMs: AT,
      assuranceFloor: "webauthn_hardware"
    });
    expect(verification.ok).toBe(true);
    expect(verification.ok === true && verification.assurance_tier).toBe("webauthn_hardware");
  });

  test("(l) KEY CUSTODY: with NO key (neither --key-file nor --key-env) it fails closed — no token minted", () => {
    const requestPath = writeRequest();
    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: { request: requestPath, keyId: "human-key-1" }
    });
    expect(result.exitCode).not.toBe(0);
  });

  test("(l) KEY CUSTODY: an unreadable key file fails closed", () => {
    const requestPath = writeRequest();
    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: { request: requestPath, keyFile: join(dir, "does-not-exist.key"), keyId: "human-key-1" }
    });
    expect(result.exitCode).not.toBe(0);
  });

  test("a missing / malformed request file fails cleanly", () => {
    const keyPath = join(dir, "human.key");
    writeFileSync(keyPath, KEY.privateKeyPem, { mode: 0o600 });
    const result = approveRunCommand.handler({
      argv: [],
      json: true,
      flags: { request: join(dir, "nope.json"), keyFile: keyPath, keyId: "human-key-1" }
    });
    expect(result.exitCode).not.toBe(0);
  });
});
