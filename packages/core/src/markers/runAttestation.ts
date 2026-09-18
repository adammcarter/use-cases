// Run attestation for the UNSIGNED verification-results ledger.
//
// THE PROBLEM. `.use-cases/verification-results.jsonl` is a plain text file that
// `verify --out` writes and `scan` reads. `scan` used to trust any line in it
// whose hashes matched the current code, which meant the keyless acceptance
// claim rewarded typing over running: appending one hand-written line moved the
// number, while genuinely driving the product moved nothing.
//
// THE FIX. Every record `verify` writes carries an HMAC over its own content,
// keyed by a secret that lives on the machine and NOT in the repo. Only the tool
// that ran the verifier holds it, so a typed line has no valid attestation and
// `scan` demotes it to UNATTESTED_LOCAL.
//
// WHAT THIS IS NOT. It is not the signing tier. There is no CI, no keyring, no
// key rotation and nothing for the user to do: the key is 32 random bytes minted
// on first use. It is tamper-EVIDENT, not tamper-PROOF — anyone who can read the
// key file can forge a record. That is the honest bound of a keyless local tier,
// and it is a large step up from "any line in a tracked file is proof".
//
// WHY THE KEY LIVES OUTSIDE THE REPO. The results ledger is transient, per-
// machine output — `use-cases init` gitignores it for exactly that reason. A key stored
// beside it would either be committed (and so forgeable by anyone with the repo)
// or need its own ignore entry in every adopting project. Keeping it under the
// user's home makes "this machine ran it" the literal meaning of the
// attestation: a results ledger someone else committed reads unattested here,
// which is correct — their run is not your evidence.
import { createHmac, randomBytes } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { canonicalJson } from "./canonicalJson.js";
import type { MarkerFs } from "./cli/io.js";

// The field carrying the attestation on a verification-result record.
export const RUN_ATTESTATION_FIELD = "run_attestation";

// Named in the value so a reader of the ledger can tell what the string is.
const RUN_ATTESTATION_ALG = "hmac-sha256";

// 32 bytes, hex. Long enough that guessing is not a strategy.
const RUN_KEY_BYTES = 32;
const RUN_KEY_PATTERN = /^[0-9a-f]{64}$/;

// Compute the attestation for one verification-result record. The record's own
// `run_attestation` field is excluded (it cannot cover itself), and the input is
// canonical JSON, so key ORDER never changes the value — the ledger is re-sorted
// and rewritten on every merge, and an honest record must survive that.
export function computeRunAttestation(record: Record<string, unknown>, key: string): string {
  const payload = { ...record };
  delete payload[RUN_ATTESTATION_FIELD];
  const mac = createHmac("sha256", Buffer.from(key, "hex"))
    .update(canonicalJson(payload))
    .digest("hex");
  return `${RUN_ATTESTATION_ALG}:${mac}`;
}

// Does this record carry an attestation this machine could have written? False
// for a record with no attestation, a tampered one, one minted elsewhere, and —
// fail closed — for every record when no key could be resolved at all.
export function verifyRunAttestation(
  record: Record<string, unknown>,
  key: string | null
): boolean {
  if (key === null || !RUN_KEY_PATTERN.test(key)) {
    return false;
  }
  const claimed = record[RUN_ATTESTATION_FIELD];
  if (typeof claimed !== "string" || claimed === "") {
    return false;
  }
  const expected = computeRunAttestation(record, key);
  // Both sides are fixed-length hex we produced, so a length mismatch is a
  // malformed claim rather than a timing signal worth protecting.
  if (claimed.length !== expected.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < expected.length; index += 1) {
    diff |= claimed.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return diff === 0;
}

// Read the machine-local run key, minting one on first use. A missing OR
// unreadable OR malformed file is replaced rather than raised: a corrupt key
// must degrade to "previous results read unattested, re-run verify", never to a
// crashed verify.
export function resolveLocalRunKey(
  keyPath: string,
  fs: MarkerFs,
  mintKey: () => string = () => randomBytes(RUN_KEY_BYTES).toString("hex")
): string {
  const existing = fs.readText(keyPath)?.trim();
  if (existing !== undefined && RUN_KEY_PATTERN.test(existing)) {
    return existing;
  }
  const minted = mintKey();
  fs.writeText(keyPath, `${minted}\n`);
  return minted;
}

// The machine-local run key, or null when no key exists yet and none may be
// minted. `scan` is strictly read-only (its whole contract), so it must never
// create a key: on a machine that has never run `verify`, every result correctly
// reads unattested.
export function readLocalRunKey(keyPath: string, fs: MarkerFs): string | null {
  const existing = fs.readText(keyPath)?.trim();
  return existing !== undefined && RUN_KEY_PATTERN.test(existing) ? existing : null;
}

// Where the machine-local run key lives by default: under the USER'S HOME, not
// the repo. `UC_RUN_KEY_FILE` overrides it — a container that wants the key on a
// mounted volume, or a test that must not touch the real home, sets that.
export function defaultRunKeyPath(env: NodeJS.ProcessEnv = process.env): string {
  const override = env.UC_RUN_KEY_FILE;
  if (typeof override === "string" && override.trim() !== "") {
    return override.trim();
  }
  return join(homedir(), ".use-cases", "run-key");
}
