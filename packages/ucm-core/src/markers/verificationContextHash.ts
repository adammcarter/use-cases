// Verification context hash (closes the "weakened verifier" freshness hole).
//
// A proof event today certifies {row hash, policy hashes, binding-set hash, span
// hashes} — i.e. WHAT was verified and against WHICH code. It says nothing about
// HOW it was verified. So if someone later weakens or deletes the row's
// acceptance test while the production spans are untouched, the old proof stays
// FRESH even though the thing that proved it is gone.
//
// `computeVerificationContextHash` binds a proof to its verifier context: the
// row's verification_policy, the RESOLVED verifier(s) it demands (id, kind,
// evidence_kind, command argv, timeout), the byte contents of every declared
// input file (e.g. the acceptance test itself), and the repo lockfile. The hash
// is embedded in the proof and re-derived at scan time; if it drifts, the proof
// is no longer FRESH.
//
// Pure + deterministic: file reads go through an injected seam, a missing input
// is an explicit `absent` marker (never an error), inputs are sorted+deduped, and
// the result depends ONLY on the declared inputs + lockfile + policy + verifiers —
// never on unrelated files in the tree.
import { isAbsolute, join } from "node:path";
import { canonicalJsonSha256, sha256 } from "./canonicalJson.js";
import { resolveRowVerifiers, type VerifierResolution } from "./verifierResolver.js";

// The id of this hashing algorithm, embedded alongside the hash in proof events.
export const VERIFICATION_CONTEXT_HASH_ID = "ucase-verification-context-hash-v1";

// Deterministic sentinel for a declared input (or lockfile) that does not exist.
// Distinct from any real `sha256:...` value, so absent != present-but-empty.
const ABSENT_CONTENT = "absent";

// The repo lockfile whose contents pin the toolchain a verifier would run under.
const DEFAULT_LOCKFILE = "pnpm-lock.yaml";

// Minimal read-only fs seam (a subset of MarkerFs) so callers can inject a fake.
export interface VerificationContextFs {
  // UTF-8 text, or null when the path does not exist.
  readText(path: string): string | null;
}

export interface VerificationContextHashArgs {
  // The row's raw verification_policy object (hashed verbatim).
  verificationPolicy: unknown;
  // The resolved verifier(s) the policy demands (from resolveRowVerifiers).
  verifiers: ReadonlyArray<VerifierResolution>;
  // Root the declared inputs + lockfile are resolved against (the repo root).
  rootDir: string;
  fs: VerificationContextFs;
  // Defaults to "pnpm-lock.yaml".
  lockfileName?: string;
}

// sha256 of a file's bytes, or the ABSENT sentinel when it does not exist.
function contentMarker(fs: VerificationContextFs, rootDir: string, relOrAbs: string): string {
  const path = isAbsolute(relOrAbs) ? relOrAbs : join(rootDir, relOrAbs);
  const text = fs.readText(path);
  return text === null ? ABSENT_CONTENT : sha256(text);
}

// Canonical, order-stable projection of one resolved/blocked verifier. Only the
// fields that define HOW verification runs are hashed (line/format independent).
function verifierToCanon(verifier: VerifierResolution): Record<string, unknown> {
  if (verifier.status === "resolved") {
    const canon: Record<string, unknown> = {
      verifier_id: verifier.verifier_id,
      status: verifier.status,
      kind: verifier.kind,
      evidence_kind: verifier.evidence_kind,
      command: verifier.command
    };
    if (verifier.timeout_seconds !== undefined) {
      canon.timeout_seconds = verifier.timeout_seconds;
    }
    return canon;
  }
  return { verifier_id: verifier.verifier_id, status: verifier.status, reason: verifier.reason };
}

// Compute the verification context hash for a row given its already-resolved
// verifiers. Returns "sha256:<hex>".
export function computeVerificationContextHash(args: VerificationContextHashArgs): string {
  const lockfileName = args.lockfileName ?? DEFAULT_LOCKFILE;

  // Verifiers sorted by id for stability (resolveRowVerifiers already sorts, but
  // this keeps the hash independent of caller ordering).
  const verifiers = [...args.verifiers]
    .sort((left, right) =>
      left.verifier_id < right.verifier_id ? -1 : left.verifier_id > right.verifier_id ? 1 : 0
    )
    .map(verifierToCanon);

  // Union of every resolved verifier's declared inputs, deduped + sorted, each
  // paired with the sha256 of its current bytes (or the absent marker).
  const inputPaths = new Set<string>();
  for (const verifier of args.verifiers) {
    if (verifier.status === "resolved") {
      for (const input of verifier.inputs) {
        inputPaths.add(input);
      }
    }
  }
  const inputs = [...inputPaths]
    .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
    .map((path) => ({ path, content_sha256: contentMarker(args.fs, args.rootDir, path) }));

  return canonicalJsonSha256({
    verification_policy: args.verificationPolicy ?? null,
    verifiers,
    inputs,
    lockfile_sha256: contentMarker(args.fs, args.rootDir, lockfileName)
  });
}

export interface RowVerificationContextHashArgs {
  // The row/use-case id; substituted for {slug} in verifier commands/inputs.
  slug: string;
  verificationPolicy: unknown;
  rootDir: string;
  fs: VerificationContextFs;
  lockfileName?: string;
}

// Convenience: resolve a row's verifiers, then compute its context hash. This is
// the single entry point both `prove` (to embed) and `scan` (to re-derive) use,
// so the embedded and recomputed hashes are guaranteed to agree byte-for-byte.
export function computeRowVerificationContextHash(args: RowVerificationContextHashArgs): string {
  const verifiers = resolveRowVerifiers({ slug: args.slug, verification_policy: args.verificationPolicy });
  return computeVerificationContextHash({
    verificationPolicy: args.verificationPolicy,
    verifiers,
    rootDir: args.rootDir,
    fs: args.fs,
    lockfileName: args.lockfileName
  });
}
