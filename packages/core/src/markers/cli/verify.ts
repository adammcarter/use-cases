// `verify` command core (Phase: verifiers/markers v2).
//
// Runs a row's resolved verifier(s) and records the result — WITHOUT any signing
// key. Unlike `prove`, verify never signs or appends to the trusted evidence
// ledger; it produces an unsigned `ucase-verification-result-v1` results ledger.
// The actual verifier process is run through an INJECTED spawn runner (default =
// node:child_process spawnSync in the repo cwd), so tests inject a fake and never
// shell out.
//
// For each targeted (bound) row it recomputes the same hashes prove/scan do — row
// hash, binding-set hash, per-binding span hashes, and the verification context
// hash — so a verify result and a proof for the same row agree byte-for-byte. A
// row whose verifier cannot be resolved is recorded as `blocked` (never crashes).
import { spawnSync } from "node:child_process";
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import { sha256 } from "../canonicalJson.js";
import { computeRowHash } from "../rowHash.js";
import { computeBindingSetHash } from "../bindingSetHash.js";
import { computeRowVerificationContextHash } from "../verificationContextHash.js";
import { resolveRowVerifiers, type ResolvedVerifier } from "../verifierResolver.js";
import type { PublicKeyResolver } from "../proofSignature.js";
import type { CurrentBindingRecord } from "../scanner.js";
import type { GitRunner } from "../appendOnly.js";
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import { prepareScan } from "./scan.js";
import { registeredBindingsForRow } from "./shared.js";

// The schema id of one unsigned verification result line.
export const VERIFICATION_RESULT_SCHEMA_ID = "ucase-verification-result-v1";

// One verifier invocation, handed to the injected spawn runner.
export interface VerifySpawnRequest {
  command: string[];
  cwd: string;
  timeout_seconds?: number;
}

// The runner's verdict for one verifier invocation.
export interface VerifySpawnResult {
  exit_code: number;
  timed_out: boolean;
  stdout: string;
  stderr: string;
}

// Injected so verify never shells out in tests. Default below uses spawnSync.
export type VerifySpawnRunner = (request: VerifySpawnRequest) => VerifySpawnResult;

// One emitted line of the results ledger. status is the aggregate row verdict;
// the verifier_* / exit_code / stdout|stderr_sha256 fields describe the verifier
// that decided that verdict (the first blocked, else the first failing, else the
// single/first passing verifier).
export interface VerificationResultRecord {
  schema: typeof VERIFICATION_RESULT_SCHEMA_ID;
  row_id: string;
  slug: string;
  status: "pass" | "fail" | "blocked";
  evidence_kind: string | null;
  verifier_id: string | null;
  verifier_kind: string | null;
  exit_code: number | null;
  row_hash: string;
  binding_set_hash: string;
  span_sha256s: string[];
  verification_context_hash: string;
  stdout_sha256: string | null;
  stderr_sha256: string | null;
  created_at: string;
}

export interface VerifyCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  publicKeyResolver: PublicKeyResolver;
  // See ScanCommandOptions.trustedKeyConfigured. verify never CONSUMES signed
  // proofs, so with no key configured a missing-key failure never blocks it.
  trustedKeyConfigured?: boolean;
  generatedAt: string;
  // Target selection: every bound row, or one row.
  all?: boolean;
  rowId?: string;
  // When set, the results ledger is written here (one JSONL line per row).
  outPath?: string;
  // Injected runner; defaults to spawnSync in the repo cwd.
  spawnRunner?: VerifySpawnRunner;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  baseRef?: string;
  gitRunner?: GitRunner;
  repoCwd?: string;
}

export interface VerifyCommandResult {
  exit_code: number;
  ok: boolean;
  command: "verify";
  results: VerificationResultRecord[];
  out_path: string | null;
  errors: Array<{ code: string; message: string }>;
}

function fail(
  partial: Partial<VerifyCommandResult> & { exit_code: number }
): VerifyCommandResult {
  return {
    command: "verify",
    ok: partial.exit_code === 0,
    results: partial.results ?? [],
    out_path: partial.out_path ?? null,
    errors: partial.errors ?? [],
    ...partial
  };
}

// Default runner: a real subprocess in the repo cwd. NEVER invoked by tests
// (they inject a fake), so it is deterministic-by-omission here.
function nodeSpawnRunner(request: VerifySpawnRequest): VerifySpawnResult {
  const [command, ...args] = request.command;
  const outcome = spawnSync(command, args, {
    cwd: request.cwd,
    encoding: "utf8",
    timeout: request.timeout_seconds !== undefined ? request.timeout_seconds * 1000 : undefined
  });
  const timedOut =
    outcome.error !== undefined &&
    (outcome.error as { code?: string }).code === "ETIMEDOUT";
  const exitCode =
    typeof outcome.status === "number" ? outcome.status : timedOut ? 124 : 1;
  return {
    exit_code: exitCode,
    timed_out: timedOut,
    stdout: outcome.stdout ?? "",
    stderr: outcome.stderr ?? ""
  };
}

export function runVerifyCommand(options: VerifyCommandOptions): VerifyCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const spawn = options.spawnRunner ?? nodeSpawnRunner;
  const contextRoot = options.repoCwd ?? options.productRoot;

  if (!options.all && !options.rowId) {
    return fail({
      exit_code: 2,
      errors: [{ code: "NO_TARGET", message: "verify requires --all or --row <slug>" }]
    });
  }

  // Run scan first (same pipeline prove uses).
  const prepared = prepareScan({
    context: options.context,
    productRoot: options.productRoot,
    bindingsPath: options.bindingsPath,
    evidencePath: options.evidencePath,
    policyMode: "feature",
    publicKeyResolver: options.publicKeyResolver,
    trustedKeyConfigured: options.trustedKeyConfigured,
    generatedAt: options.generatedAt,
    fs,
    commentConfig: options.commentConfig,
    baseRef: options.baseRef,
    gitRunner: options.gitRunner,
    repoCwd: options.repoCwd
  });

  // `verify` RUNS the row's verifier command and writes an UNSIGNED results
  // ledger — it never CONSUMES signed proofs, so it does NOT need --public-key. A
  // pure missing-key failure (a signed proof present, no key to check it) is
  // therefore NOT a reason to abort: verify still verifies bound rows. Only REAL
  // ledger corruption (BAD_SIGNATURE, malformed/append-violating/schema-invalid,
  // or any registry error) blocks the run with LEDGER_INVALID (exit 4).
  if (prepared.registryErrors.length > 0 || prepared.evidenceIntegrityErrors.length > 0) {
    const detail = [
      ...prepared.registryErrors.map((error) => ({
        code: error.code,
        message: error.line == null ? error.message : `line ${error.line}: ${error.message}`
      })),
      ...prepared.evidenceIntegrityErrors.map((error) => ({
        code: error.code,
        message: error.line == null ? error.message : `line ${error.line}: ${error.message}`
      }))
    ];
    return fail({
      exit_code: 4,
      errors: [
        { code: "LEDGER_INVALID", message: "registry or evidence ledger failed validation" },
        ...detail
      ]
    });
  }

  // Resolve target rows. A target is a BOUND row (status !== UNBOUND); an explicit
  // --row that does not exist is a hard error.
  let targetRowIds: string[];
  if (options.rowId) {
    const statusRow = prepared.status.rows.find((row) => row.row_id === options.rowId);
    const loadedRow = prepared.loaded.rows.find((row) => row.row_id === options.rowId);
    if (!statusRow || !loadedRow) {
      return fail({
        exit_code: 2,
        errors: [{ code: "ROW_NOT_FOUND", message: `row ${options.rowId} is not a known use-case row` }]
      });
    }
    // UNBOUND is not a target (consistent with scan): nothing to verify.
    targetRowIds = statusRow.status === "UNBOUND" ? [] : [options.rowId];
  } else {
    targetRowIds = prepared.status.rows
      .filter((row) => row.status !== "UNBOUND")
      .map((row) => row.row_id)
      .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  }

  const results: VerificationResultRecord[] = [];
  for (const rowId of targetRowIds) {
    const statusRow = prepared.status.rows.find((row) => row.row_id === rowId);
    const loadedRow = prepared.loaded.rows.find((row) => row.row_id === rowId);
    if (!statusRow || !loadedRow) {
      continue;
    }

    const registeredSlugs = new Set(statusRow.known_binding_slugs);
    const bindings = registeredBindingsForRow(prepared.scan.bindings, rowId, registeredSlugs);

    const rowHash = computeRowHash(loadedRow);
    const bindingSetHash = computeBindingSetHash(
      rowId,
      bindings.map((binding) => ({
        binding_slug: binding.binding_slug,
        row_id: binding.row_id,
        file_path: binding.file_path,
        extent_kind: binding.extent_kind,
        recognizer_id: binding.recognizer_id,
        span_canon_id: binding.span_canon_id,
        span_sha256: binding.span.sha256
      }))
    );
    const spanHashes = bindings
      .map((binding) => binding.span.sha256)
      .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
    const contextHash = computeRowVerificationContextHash({
      slug: rowId,
      verificationPolicy: loadedRow.verification_policy,
      rootDir: contextRoot,
      fs,
      workspaceVerifiers: options.context.verifiers
    });

    const base = {
      schema: VERIFICATION_RESULT_SCHEMA_ID,
      row_id: rowId,
      slug: rowId,
      row_hash: rowHash,
      binding_set_hash: bindingSetHash,
      span_sha256s: spanHashes,
      verification_context_hash: contextHash,
      created_at: options.generatedAt
    } as const;

    // An INVALID row (binding integrity errors) cannot be verified -> fail.
    if (statusRow.status === "INVALID") {
      results.push({
        ...base,
        status: "fail",
        evidence_kind: null,
        verifier_id: null,
        verifier_kind: null,
        exit_code: null,
        stdout_sha256: null,
        stderr_sha256: null
      });
      continue;
    }

    // Same workspace verifiers prove/scan use, so the verifier this RUNS is the
    // one the embedded + recomputed context hashes are derived from.
    const verifiers = resolveRowVerifiers(
      { slug: rowId, verification_policy: loadedRow.verification_policy },
      options.context.verifiers
    );

    // A bound row that demands NO verifier (e.g. mode:none) can't be certified by
    // verify -> blocked (recorded, surfaced, never crashes).
    const blocked = verifiers.find((verifier) => verifier.status === "blocked");
    if (verifiers.length === 0 || blocked) {
      results.push({
        ...base,
        status: "blocked",
        evidence_kind: null,
        verifier_id: blocked ? blocked.verifier_id : null,
        verifier_kind: null,
        exit_code: null,
        stdout_sha256: null,
        stderr_sha256: null
      });
      continue;
    }

    // Every verifier resolved: run each, aggregate to a pass/fail row verdict.
    const resolved = verifiers as ResolvedVerifier[];
    const runs = resolved.map((verifier) => ({
      verifier,
      outcome: spawn({
        command: verifier.command,
        cwd: contextRoot,
        timeout_seconds: verifier.timeout_seconds
      })
    }));
    const firstFailure = runs.find(
      (run) => run.outcome.exit_code !== 0 || run.outcome.timed_out
    );
    const decisive = firstFailure ?? runs[0];

    results.push({
      ...base,
      status: firstFailure ? "fail" : "pass",
      evidence_kind: decisive.verifier.evidence_kind,
      verifier_id: decisive.verifier.verifier_id,
      verifier_kind: decisive.verifier.kind,
      exit_code: decisive.outcome.exit_code,
      stdout_sha256: sha256(decisive.outcome.stdout),
      stderr_sha256: sha256(decisive.outcome.stderr)
    });
  }

  // Write the results ledger (one JSONL line per row) if requested. This is an
  // unsigned per-run snapshot — NOT the append-only trusted evidence ledger.
  let outPath: string | null = null;
  if (options.outPath) {
    const body = results.map((record) => JSON.stringify(record)).join("\n");
    fs.writeText(options.outPath, body === "" ? "" : `${body}\n`);
    outPath = options.outPath;
  }

  // Exit 0 only if every targeted row passed; any fail/blocked is nonzero.
  const allPass = results.every((record) => record.status === "pass");
  return fail({
    exit_code: allPass ? 0 : 1,
    results,
    out_path: outPath
  });
}
