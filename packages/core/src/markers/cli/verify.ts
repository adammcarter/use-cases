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
import type { FreshnessInputRow } from "../freshness.js";
import { computeBindingSetHash } from "../bindingSetHash.js";
import { computeRowVerificationContextHash } from "../verificationContextHash.js";
import { resolveRowVerifiers, type ResolvedVerifier } from "../verifierResolver.js";
import type { PublicKeyResolver } from "../proofSignature.js";
import type { CurrentBindingRecord } from "../scanner.js";
import type { GitRunner } from "../appendOnly.js";
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import { prepareScan } from "./scan.js";
import { registeredBindingsForRow, rowVariants } from "./shared.js";

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
  // Set only for a variant record (row_id `<family>::<key>`): the variant's key.
  // Additive/optional — an ordinary row's record omits it, so existing ledgers and
  // older readers are unaffected.
  variant_key?: string;
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
  // Show WHAT would run, run nothing, write nothing. `acceptance` verifiers are
  // often a full build — the single biggest reason an agent lets evidence go
  // stale is that it cannot tell what a verify will cost before paying for it.
  dryRun?: boolean;
  // Injected runner; defaults to spawnSync in the repo cwd.
  spawnRunner?: VerifySpawnRunner;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  baseRef?: string;
  gitRunner?: GitRunner;
  repoCwd?: string;
}

// What a --dry-run says it WOULD do for one row: nothing is run and nothing is
// written, so this is a plan, never evidence.
export interface VerifyPlannedRow {
  row_id: string;
  verifier_id: string | null;
  command: string[] | null;
  // "run" | "blocked" (no resolvable verifier) | "invalid" (binding integrity).
  disposition: "run" | "blocked" | "invalid";
}

export interface VerifyCommandResult {
  exit_code: number;
  ok: boolean;
  command: "verify";
  results: VerificationResultRecord[];
  out_path: string | null;
  // Only populated by --dry-run. Empty on a real run.
  planned?: VerifyPlannedRow[];
  dry_run?: boolean;
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

  // --dry-run: resolve exactly what a real run WOULD execute, then stop. Nothing
  // is spawned, no ledger is written, and no result record is minted — a plan is
  // not evidence.
//: @use-case:lifecycle.signals.verify_can_be_previewed
  if (options.dryRun) {
    const planned: VerifyPlannedRow[] = [];
    for (const rowId of targetRowIds) {
      const statusRow = prepared.status.rows.find((row) => row.row_id === rowId);
      const loadedRow = prepared.loaded.rows.find((row) => row.row_id === rowId);
      if (!statusRow || !loadedRow) {
        continue;
      }
      if (statusRow.status === "INVALID") {
        planned.push({ row_id: rowId, verifier_id: null, command: null, disposition: "invalid" });
        continue;
      }
      // A variant family plans one entry per variant (with {variant} substituted); an
      // ordinary row plans as itself. Mirrors the real-run fan-out so the preview is
      // exactly what a run WOULD execute.
      const variants = rowVariants(loadedRow);
      const planUnits =
        variants.length === 0
          ? [{ recordRowId: rowId, variantKey: undefined as string | undefined }]
          : variants.map((variant) => ({ recordRowId: `${rowId}::${variant.key}`, variantKey: variant.key as string | undefined }));
      for (const unit of planUnits) {
        const verifiers = resolveRowVerifiers(
          { slug: rowId, variant: unit.variantKey, verification_policy: loadedRow.verification_policy },
          options.context.verifiers
        );
        const blocked = verifiers.find((verifier) => verifier.status === "blocked");
        if (verifiers.length === 0 || blocked) {
          planned.push({
            row_id: unit.recordRowId,
            verifier_id: blocked ? blocked.verifier_id : null,
            command: null,
            disposition: "blocked"
          });
          continue;
        }
        for (const verifier of verifiers as ResolvedVerifier[]) {
          planned.push({
            row_id: unit.recordRowId,
            verifier_id: verifier.verifier_id,
            command: verifier.command,
            disposition: "run"
          });
        }
      }
    }
    return fail({
      exit_code: 0,
      results: [],
      out_path: null,
      planned,
      dry_run: true,
      errors: []
    });
  }
//: @use-case:end lifecycle.signals.verify_can_be_previewed

  const results: VerificationResultRecord[] = [];
  const verifyErrors: Array<{ code: string; message: string }> = [];
  for (const rowId of targetRowIds) {
    const statusRow = prepared.status.rows.find((row) => row.row_id === rowId);
    const loadedRow = prepared.loaded.rows.find((row) => row.row_id === rowId);
    if (!statusRow || !loadedRow) {
      continue;
    }

    const registeredSlugs = new Set(statusRow.known_binding_slugs);
    const bindings = registeredBindingsForRow(prepared.scan.bindings, rowId, registeredSlugs);
    const bindingSetMembers = bindings.map((binding) => ({
      binding_slug: binding.binding_slug,
      row_id: binding.row_id,
      file_path: binding.file_path,
      extent_kind: binding.extent_kind,
      recognizer_id: binding.recognizer_id,
      span_canon_id: binding.span_canon_id,
      span_sha256: binding.span.sha256
    }));
    const spanHashes = bindings
      .map((binding) => binding.span.sha256)
      .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
    // Context hash is family-level (verifier DEFINITION, not the {variant}-substituted
    // command), so a family and all its variants agree with scan/prove.
    const contextHash = computeRowVerificationContextHash({
      slug: rowId,
      verificationPolicy: loadedRow.verification_policy,
      rootDir: contextRoot,
      fs,
      workspaceVerifiers: options.context.verifiers
    });

    // A variant family fans out into one unit per declared variant; an ordinary row
    // is a single unit. Each unit produces ONE result record. The family stays the
    // bound row (slug = family id); a variant's record is keyed `<family>::<key>`.
    const variants = rowVariants(loadedRow);
    const units =
      variants.length === 0
        ? [{ recordRowId: rowId, variantKey: undefined as string | undefined }]
        : variants.map((variant) => ({
            recordRowId: `${rowId}::${variant.key}`,
            variantKey: variant.key as string | undefined
          }));

    for (const unit of units) {
      // Per-variant integrity: hash a projection carrying this variant's identity so
      // each variant's row/binding-set hash is its own; binding-set hash mixes in the
      // variant record id over the SHARED family span.
      const unitRow =
        unit.variantKey === undefined
          ? loadedRow
          : variantRowProjection(loadedRow, unit.recordRowId, unit.variantKey);
      const base = {
        schema: VERIFICATION_RESULT_SCHEMA_ID as VerificationResultRecord["schema"],
        row_id: unit.recordRowId,
        slug: unit.recordRowId,
        row_hash: computeRowHash(unitRow),
        binding_set_hash: computeBindingSetHash(unit.recordRowId, bindingSetMembers),
        span_sha256s: spanHashes,
        verification_context_hash: contextHash,
        created_at: options.generatedAt,
        ...(unit.variantKey !== undefined ? { variant_key: unit.variantKey } : {})
      };

      // An INVALID row (binding integrity errors) cannot be verified -> fail.
      if (statusRow.status === "INVALID") {
        results.push({ ...base, status: "fail", evidence_kind: null, verifier_id: null, verifier_kind: null, exit_code: null, stdout_sha256: null, stderr_sha256: null });
        continue;
      }

      // Same workspace verifiers prove/scan use; a variant substitutes {variant}.
      const verifiers = resolveRowVerifiers(
        { slug: rowId, variant: unit.variantKey, verification_policy: loadedRow.verification_policy },
        options.context.verifiers
      );

      // A bound row that demands NO verifier (e.g. mode:none) -> blocked.
      const blocked = verifiers.find((verifier) => verifier.status === "blocked");
      if (verifiers.length === 0 || blocked) {
        results.push({ ...base, status: "blocked", evidence_kind: null, verifier_id: blocked ? blocked.verifier_id : null, verifier_kind: null, exit_code: null, stdout_sha256: null, stderr_sha256: null });
        continue;
      }

      const resolved = verifiers as ResolvedVerifier[];

      // Spec error: a variant family whose command can't distinguish variants (no
      // {variant} token). Resolving with vs without the variant yields the SAME
      // command -> the run would prove every variant identically. Surface, don't run.
      if (unit.variantKey !== undefined) {
        const variantless = resolveRowVerifiers(
          { slug: rowId, verification_policy: loadedRow.verification_policy },
          options.context.verifiers
        ) as ResolvedVerifier[];
        const cannotDistinguish = resolved.every(
          (verifier, index) =>
            JSON.stringify(verifier.command) === JSON.stringify(variantless[index]?.command)
        );
        if (cannotDistinguish) {
          verifyErrors.push({
            code: "VARIANT_TOKEN_MISSING",
            message: `verifier for variant family '${rowId}' has no {variant} token, so it cannot distinguish variants; add {variant} to its command`
          });
          results.push({ ...base, status: "blocked", evidence_kind: null, verifier_id: resolved[0]?.verifier_id ?? null, verifier_kind: null, exit_code: null, stdout_sha256: null, stderr_sha256: null });
          continue;
        }
      }

      // Every verifier resolved: run each, aggregate to a pass/fail verdict.
      const runs = resolved.map((verifier) => ({
        verifier,
        outcome: spawn({ command: verifier.command, cwd: contextRoot, timeout_seconds: verifier.timeout_seconds })
      }));
      const firstFailure = runs.find((run) => run.outcome.exit_code !== 0 || run.outcome.timed_out);
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
  }

  // Write the results ledger (one JSONL line per row) if requested. This is an
  // unsigned per-run snapshot — NOT the append-only trusted evidence ledger.
  //
  // MERGE, never truncate. This run only targeted `targetRowIds`; a row it did not
  // touch still has a valid prior result, and blowing that away would silently drop
  // every other row to UNVERIFIED_LOCAL (scan reads exactly this file). So: keep the
  // rows this run did not verify, replace the ones it did. Retained rows are kept as
  // their original line text so fields this version does not model survive a merge.
  // Staleness is NOT our call here — deriveFreshness re-checks each retained record's
  // hashes against the current code and demotes it if it no longer matches.
  let outPath: string | null = null;
//: @use-case:lifecycle.signals.verify_preserves_other_rows
  if (options.outPath) {
    const supersededRowIds = new Set(results.map((record) => record.row_id));
    const merged: { rowId: string; line: string }[] = [];

    for (const raw of (fs.readText(options.outPath) ?? "").split("\n")) {
      const line = raw.trim();
      if (line === "") {
        continue;
      }
      let record: unknown;
      try {
        record = JSON.parse(line);
      } catch {
        continue; // drop a malformed line rather than propagating corruption
      }
      if (typeof record !== "object" || record === null) {
        continue;
      }
      const rowId = (record as Record<string, unknown>).row_id;
      if (typeof rowId !== "string" || supersededRowIds.has(rowId)) {
        continue; // this run re-verified the row: its fresh record wins
      }
      merged.push({ rowId, line });
    }

    for (const record of results) {
      merged.push({ rowId: record.row_id, line: JSON.stringify(record) });
    }

    // Sort by row_id so the ledger is deterministic (and diffs/merges stay sane)
    // regardless of the order rows happened to be verified in.
    merged.sort((left, right) =>
      left.rowId < right.rowId ? -1 : left.rowId > right.rowId ? 1 : 0
    );

    const body = merged.map((entry) => entry.line).join("\n");
    fs.writeText(options.outPath, body === "" ? "" : `${body}\n`);
    outPath = options.outPath;
  }
//: @use-case:end lifecycle.signals.verify_preserves_other_rows

  // Exit 0 only if every targeted row passed; any fail/blocked is nonzero.
  const allPass = results.every((record) => record.status === "pass");
  return fail({
    exit_code: allPass ? 0 : 1,
    results,
    out_path: outPath,
    errors: verifyErrors
  });
}

// A variant's row projection: the family row minus its `variants` list, carrying the
// variant's record id and key. Hashing this (computeRowHash) gives each variant a
// distinct row hash reflecting only its own identity, not its siblings'.
function variantRowProjection(
  loadedRow: FreshnessInputRow,
  recordRowId: string,
  variantKey: string
): FreshnessInputRow {
  const projection: FreshnessInputRow = {
    ...loadedRow,
    row_id: recordRowId,
    variant_key: variantKey
  };
  delete (projection as Record<string, unknown>).variants;
  return projection;
}
