// ed25519 keypair generation for the OPT-IN signed proof tier (spec 5.2/5.3).
//
// This mirrors the recipe in docs/security/key-management.md exactly: the
// private key is exported as a PKCS8 PEM and the public key as an SPKI PEM —
// the two formats `prove --signing-key-env` (via createPrivateKey) and
// `--public-key` (via createPublicKey) already consume. Everything here is pure
// crypto over in-memory values; no filesystem, git, or process access. The CLI
// layer owns where (if anywhere) the keys are written and the CI-only warning.
import { generateKeyPairSync } from "node:crypto";

// A freshly-minted ed25519 keypair in the on-disk PEM forms the tool consumes.
export interface SigningKeypair {
  // PKCS8 ed25519 PEM. The PRIVATE key — belongs only in CI secrets, never the
  // repo. Fed to `prove` through --signing-key-env.
  privatePem: string;
  // SPKI ed25519 PEM. The PUBLIC key — safe to commit; used by --public-key or a
  // keyring entry to verify proof signatures.
  publicPem: string;
}

// Generate a new ed25519 signing keypair. Each call returns a distinct pair.
export function generateSigningKeypair(): SigningKeypair {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return {
    privatePem: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
    publicPem: publicKey.export({ type: "spki", format: "pem" }).toString()
  };
}
