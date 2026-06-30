// `prove` command core (spec 8.3; markers v2 PIECE 4).
//
// prove NO LONGER runs verifier scripts itself. It CONSUMES an unsigned
// verification-results ledger (`ucase-verification-result-v1`, produced by the
// `verify` command). For each targeted row it recomputes every hash ITSELF (row,
// binding-set, span, verification-context) and appends a signed proof ONLY when
// the row's latest matching result is status:pass AND prove's freshly recomputed
// hashes EQUAL the hashes the record carries — it never trusts a record's hashes
// blindly and refuses a mismatch with a clear error.
//
// `--all` iterates every bound row (sorted). UNBOUND rows are skipped (not a
// failure); INVALID rows are refused; an already-FRESH row is skipped unless
// `--refresh`; a bound row with a missing/failed/blocked/mismatched result yields
// no proof and a failure. Appends are NON-ATOMIC: passing rows are appended even
// when a sibling row fails, and the command then exits nonzero.
//
// The dangerous "assume verification passed" seam is `unsafeAssumeVerificationResult`
// and is honoured ONLY when env UCP_ALLOW_UNSAFE_VERIFICATION=1 is set; otherwise
// it is ignored, so it can never manufacture a green proof in normal operation.
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import { ROW_HASH_ID, SPAN_CANON_ID, BINDING_SET_HASH_ID } from "../constants.js";
import { computeRowHash } from "../rowHash.js";
import {
  computeApprovalPolicyHash,
  computeVerificationPolicyHash
} from "../policyHash.js";
import { computeBindingSetHash } from "../bindingSetHash.js";
import {
  VERIFICATION_CONTEXT_HASH_ID,
  computeRowVerificationContextHash
} from "../verificationContextHash.js";
import {
  GENESIS_ENTRY_HASH,
  TRUSTED_CI_PRODUCER_KIND,
  computeLedgerEntryHash,
  readEvidenceJsonl,
  type ProofEvent
} from "../evidenceLedger.js";
import {
  signEvent,
  type PemOrKeyObject,
  type PublicKeyResolver
} from "../proofSignature.js";
import type { CiAuthority } from "../ciAuthority.js";
import type { CurrentBindingRecord } from "../scanner.js";
import type { FreshnessInputRow } from "../freshness.js";
import type { GitRunner } from "../appendOnly.js";
import { appendJsonlLine, nodeMarkerFs, type MarkerFs } from "./io.js";
import { prepareScan, type ScanPreparation } from "./scan.js";
import { registeredBindingsForRow } from "./shared.js";
import type { VerificationResultRecord } from "./verify.js";

// The env var that must equal "1" for the dangerous unsafe-assume seam to be
// honoured. Absent/any-other value -> the seam is silently ignored.
export const ALLOW_UNSAFE_VERIFICATION_ENV = "UCP_ALLOW_UNSAFE_VERIFICATION";

export interface ProveSigningKey {
  privateKey: PemOrKeyObject;
  keyId: string;
}

export interface ProveProducerInfo {
  id?: string;
  version?: string;
  ci_run_id?: string;
  repo?: string;
  commit?: string;
}

export interface ProveCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  publicKeyResolver: PublicKeyResolver;
  // Single-row target. Either this or `all` must be set.
  rowId?: string;
  // Iterate every bound row (sorted).
  all?: boolean;
  // Re-sign rows that are already FRESH (default: skip them).
  refresh?: boolean;
  trustedCi?: boolean;
  // An explicit append request; without trusted credentials this is exit 6.
  append?: boolean;
  dryRun?: boolean;
  // The consumed verification-results ledger (from `verify --out`). prove finds
  // the latest record per row, never re-runs the verifier.
  verificationResults?: VerificationResultRecord[];
  // DANGEROUS test seam: assume the row's verification passed. Honoured ONLY when
  // env UCP_ALLOW_UNSAFE_VERIFICATION=1 is set; otherwise ignored.
  unsafeAssumeVerificationResult?: "pass";
  signingKey?: ProveSigningKey;
  producer?: ProveProducerInfo;
  // OPTIONAL CI-neutral provenance authority embedded into every proof this run
  // appends. Built into the event before signing (the signature covers it). The
  // GitHub-shaped `producer` block is kept exactly as before, beside it.
  authority?: CiAuthority;
  generatedAt: string;
  // Injectable so tests can assert on a deterministic event id.
  idFactory?: () => string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  baseRef?: string;
  gitRunner?: GitRunner;
  repoCwd?: string;
}

// The per-row verdict. `signed` appended a proof; `candidate` would pass but was
// not appended (untrusted/dry-run); `skipped_*` did no work; `failed` was refused.
export type ProveRowStatus =
  | "signed"
  | "candidate"
  | "skipped_unbound"
  | "skipped_fresh"
  | "failed";

export interface ProveRowResult {
  row_id: string;
  status: ProveRowStatus;
  // Machine-readable failure/skip code (null on success skips with no detail).
  reason: string | null;
  message: string | null;
  proof_event_appended: boolean;
  event_id: string | null;
  row_hash: string | null;
  binding_set_hash: string | null;
}

export interface ProveCommandResult {
  exit_code: number;
  ok: boolean;
  command: "prove";
  trusted: boolean;
  rows: ProveRowResult[];
  proof_events_appended: number;
  errors: Array<{ code: string; message: string }>;
}

function commandResult(
  partial: Partial<ProveCommandResult> & { exit_code: number }
): ProveCommandResult {
  return {
    command: "prove",
    ok: partial.exit_code === 0,
    trusted: partial.trusted ?? false,
    rows: partial.rows ?? [],
    proof_events_appended: partial.proof_events_appended ?? 0,
    errors: partial.errors ?? [],
    ...partial
  };
}

function rowResult(
  rowId: string,
  status: ProveRowStatus,
  extra: Partial<ProveRowResult> = {}
): ProveRowResult {
  return {
    row_id: rowId,
    status,
    reason: extra.reason ?? null,
    message: extra.message ?? null,
    proof_event_appended: extra.proof_event_appended ?? false,
    event_id: extra.event_id ?? null,
    row_hash: extra.row_hash ?? null,
    binding_set_hash: extra.binding_set_hash ?? null
  };
}

// The minimal verification facts that flow into a proof's `verification` block.
interface ProofVerification {
  command_id: string;
  started_at: string;
  completed_at: string;
  artifacts: Array<{ kind: string; path: string; sha256: string }>;
}

export function runProveCommand(options: ProveCommandOptions): ProveCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const trusted = options.trustedCi === true;
  const dryRun = options.dryRun === true;
  const contextRoot = options.repoCwd ?? options.productRoot;
  const allowUnsafe = process.env[ALLOW_UNSAFE_VERIFICATION_ENV] === "1";

  // Untrusted explicit append attempt is the highest-priority refusal (spec 8.3).
  if (options.append && !trusted) {
    return commandResult({
      exit_code: 6,
      errors: [
        { code: "UNTRUSTED_APPEND", message: "an append was requested without trusted-CI credentials" }
      ]
    });
  }

  if (!options.all && !options.rowId) {
    return commandResult({
      exit_code: 2,
      trusted,
      errors: [{ code: "NO_TARGET", message: "prove requires --all or --row <slug>" }]
    });
  }

  // Run scan first (spec 8.3 step 1): registry/evidence validation + per-row state.
  const prepared = prepareScan({
    context: options.context,
    productRoot: options.productRoot,
    bindingsPath: options.bindingsPath,
    evidencePath: options.evidencePath,
    policyMode: "feature",
    publicKeyResolver: options.publicKeyResolver,
    generatedAt: options.generatedAt,
    fs,
    commentConfig: options.commentConfig,
    baseRef: options.baseRef,
    gitRunner: options.gitRunner,
    repoCwd: options.repoCwd
  });

  if (prepared.registryErrors.length > 0 || prepared.evidenceErrors.length > 0) {
    return commandResult({
      exit_code: 4,
      trusted,
      errors: [{ code: "LEDGER_INVALID", message: "registry or evidence ledger failed validation" }]
    });
  }

  // A trusted, non-dry-run prove will append signed proofs, which requires a key.
  const willAppend = trusted && !dryRun;
  if (willAppend && !options.signingKey) {
    return commandResult({
      exit_code: 2,
      trusted,
      errors: [{ code: "SIGNING_KEY_MISSING", message: "trusted-CI prove requires a signing key" }]
    });
  }

  // Resolve the target row ids. A single --row that does not exist is a hard error.
  let targetRowIds: string[];
  if (options.rowId) {
    const statusRow = prepared.status.rows.find((row) => row.row_id === options.rowId);
    const loadedRow = prepared.loaded.rows.find((row) => row.row_id === options.rowId);
    if (!statusRow || !loadedRow) {
      return commandResult({
        exit_code: 2,
        trusted,
        errors: [{ code: "ROW_NOT_FOUND", message: `row ${options.rowId} is not a known use-case row` }]
      });
    }
    targetRowIds = [options.rowId];
  } else {
    targetRowIds = prepared.status.rows
      .map((row) => row.row_id)
      .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
  }

  const idFactory = options.idFactory ?? generateEventId;
  const rows: ProveRowResult[] = [];
  let appended = 0;

  for (const rowId of targetRowIds) {
    const evaluation = proveOneRow({
      rowId,
      options,
      prepared,
      fs,
      contextRoot,
      trusted,
      dryRun,
      allowUnsafe,
      idFactory
    });
    rows.push(evaluation);
    if (evaluation.proof_event_appended) {
      appended += 1;
    }
  }

  // Non-atomic: passing rows are already appended above; the command exits nonzero
  // iff any targeted row failed.
  const anyFailed = rows.some((row) => row.status === "failed");
  return commandResult({
    exit_code: anyFailed ? 5 : 0,
    trusted,
    rows,
    proof_events_appended: appended
  });
}

interface ProveOneRowArgs {
  rowId: string;
  options: ProveCommandOptions;
  prepared: ScanPreparation;
  fs: MarkerFs;
  contextRoot: string;
  trusted: boolean;
  dryRun: boolean;
  allowUnsafe: boolean;
  idFactory: () => string;
}

function proveOneRow(args: ProveOneRowArgs): ProveRowResult {
  const { rowId, options, prepared, fs, contextRoot, trusted, dryRun, allowUnsafe, idFactory } = args;
  const statusRow = prepared.status.rows.find((row) => row.row_id === rowId);
  const loadedRow = prepared.loaded.rows.find((row) => row.row_id === rowId);
  if (!statusRow || !loadedRow) {
    return rowResult(rowId, "failed", {
      reason: "ROW_NOT_FOUND",
      message: `row ${rowId} is not a known use-case row`
    });
  }

  // UNBOUND -> skip (not a failure); INVALID -> refuse (failure).
  if (statusRow.status === "UNBOUND") {
    return rowResult(rowId, "skipped_unbound", { message: "no binding; nothing to prove" });
  }
  if (statusRow.status === "INVALID") {
    return rowResult(rowId, "failed", {
      reason: "ROW_INVALID",
      message: `row ${rowId} has binding integrity errors; cannot prove`
    });
  }

  // Recompute every hash from scratch (never trust the record's hashes blindly).
  const registeredSlugs = new Set(statusRow.known_binding_slugs);
  const bindings = registeredBindingsForRow(prepared.scan.bindings, rowId, registeredSlugs);
  const rowHash = computeRowHash(loadedRow);
  const verificationPolicyHash = computeVerificationPolicyHash(loadedRow.verification_policy);
  const approvalPolicyHash = computeApprovalPolicyHash(loadedRow.approval_policy);
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

  const hashes = { row_hash: rowHash, binding_set_hash: bindingSetHash };

  // Already FRESH -> skip unless an explicit refresh was requested.
  if (statusRow.status === "FRESH" && options.refresh !== true) {
    return rowResult(rowId, "skipped_fresh", { ...hashes, message: "already FRESH" });
  }

  // Decide acceptance. The unsafe seam (env-gated) short-circuits the results
  // lookup; otherwise prove consumes the latest matching verification-result.
  let verification: ProofVerification;
  if (options.unsafeAssumeVerificationResult === "pass" && allowUnsafe) {
    verification = {
      command_id: `acceptance.${rowId}`,
      started_at: options.generatedAt,
      completed_at: options.generatedAt,
      artifacts: []
    };
  } else {
    const record = latestResultFor(rowId, options.verificationResults);
    if (!record) {
      return rowResult(rowId, "failed", {
        ...hashes,
        reason: "NO_PASSING_RESULT",
        message: `no verification result for row ${rowId}; run \`ucp verify --row ${rowId} --out <path>\` first`
      });
    }
    if (record.status === "blocked") {
      return rowResult(rowId, "failed", {
        ...hashes,
        reason: "RESULT_BLOCKED",
        message: `verification for ${rowId} is blocked (verifier could not be resolved)`
      });
    }
    if (record.status !== "pass") {
      return rowResult(rowId, "failed", {
        ...hashes,
        reason: "RESULT_FAILED",
        message: `verification for ${rowId} did not pass`
      });
    }

    // status:pass -> prove's own hashes must EQUAL the record's. Refuse a mismatch.
    const mismatches: string[] = [];
    if (record.row_hash !== rowHash) mismatches.push("row_hash");
    if (record.binding_set_hash !== bindingSetHash) mismatches.push("binding_set_hash");
    if (!stringArraysEqual(record.span_sha256s, spanHashes)) mismatches.push("span_sha256s");
    if (record.verification_context_hash !== contextHash) mismatches.push("verification_context_hash");
    if (mismatches.length > 0) {
      return rowResult(rowId, "failed", {
        ...hashes,
        reason: "HASH_MISMATCH",
        message: `verification result for ${rowId} is stale; recomputed hashes differ (${mismatches.join(", ")})`
      });
    }

    verification = {
      command_id: record.verifier_id ?? `acceptance.${rowId}`,
      started_at: record.created_at,
      completed_at: record.created_at,
      artifacts: []
    };
  }

  // Accepted. Candidate-only when not trusted or explicitly dry-run (never appends).
  if (!trusted || dryRun) {
    return rowResult(rowId, "candidate", { ...hashes, message: "verification accepted; not appended" });
  }

  // Trusted append (signingKey guaranteed present by the pre-flight check).
  const signingKey = options.signingKey as ProveSigningKey;
  // Tamper-evident chain: read the CURRENT ledger tail so the new entry's
  // entry_index / previous_entry_hash chain onto whatever is already appended.
  // Re-reading here (not caching) keeps a multi-row `--all` run correct: each
  // earlier append in the SAME run is on disk by the time the next row chains.
  const tail = readLedgerTail(fs, options.evidencePath);
  const unsigned = buildProofEvent({
    eventId: idFactory(),
    createdAt: options.generatedAt,
    rowId,
    rowHash,
    verificationPolicyHash,
    approvalPolicyHash,
    bindingSetHash,
    contextHash,
    bindings,
    verification,
    producer: options.producer,
    authority: options.authority,
    entryIndex: tail.count,
    previousEntryHash: tail.lastEntry
      ? computeLedgerEntryHash(tail.lastEntry)
      : GENESIS_ENTRY_HASH
  });
  // The chain fields live INSIDE the event before signing, so the signature
  // covers them and they cannot be forged or reordered after the fact.
  const signed = signEvent(unsigned, signingKey.privateKey, signingKey.keyId);
  appendJsonlLine(fs, options.evidencePath, JSON.stringify(signed));

  return rowResult(rowId, "signed", {
    ...hashes,
    proof_event_appended: true,
    event_id: signed.event_id
  });
}

// The current ledger tail for the tamper-evident chain: the entry count (the
// next entry's absolute index) and the last parsed entry (to hash as the next
// entry's previous_entry_hash). A missing/empty ledger yields count 0 / null.
function readLedgerTail(
  fs: MarkerFs,
  path: string
): { count: number; lastEntry: ProofEvent | null } {
  const read = readEvidenceJsonl(fs.readText(path) ?? "");
  const count = read.lines.length;
  const lastEntry = count > 0 ? (read.lines[count - 1].value as ProofEvent) : null;
  return { count, lastEntry };
}

// The latest (last-written) verification-result record for a row, or undefined.
function latestResultFor(
  rowId: string,
  records: VerificationResultRecord[] | undefined
): VerificationResultRecord | undefined {
  if (!records) {
    return undefined;
  }
  let latest: VerificationResultRecord | undefined;
  for (const record of records) {
    if (record.row_id === rowId) {
      latest = record;
    }
  }
  return latest;
}

function stringArraysEqual(left: string[], right: string[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  return left.every((value, index) => value === right[index]);
}

// 26-char Crockford-base32 ULID-shaped id. Deterministic ids are injectable via
// `idFactory` for tests that assert on event ids; here uniqueness is what matters.
function generateEventId(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let out = "";
  for (let i = 0; i < 26; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

interface BuildProofArgs {
  eventId: string;
  createdAt: string;
  rowId: string;
  rowHash: string;
  verificationPolicyHash: string;
  approvalPolicyHash: string;
  bindingSetHash: string;
  contextHash: string;
  bindings: CurrentBindingRecord[];
  verification: ProofVerification;
  producer?: ProveProducerInfo;
  // OPTIONAL CI-neutral provenance authority (additive). Built into the event
  // before signing when present; omitted entirely when absent.
  authority?: CiAuthority;
  // Tamper-evident chain fields (additive). Built into the event before signing.
  entryIndex: number;
  previousEntryHash: string;
}

// Build the unsigned proof event. producer.kind is ALWAYS forced to the trusted
// constant — an agent can never set it (spec 8.3 must-not 5).
function buildProofEvent(args: BuildProofArgs): Omit<ProofEvent, "signature"> {
  return {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: args.eventId,
    created_at: args.createdAt,
    producer: {
      kind: TRUSTED_CI_PRODUCER_KIND,
      id: args.producer?.id ?? "ci/use-cases-prover",
      version: args.producer?.version ?? "0.1.0",
      ci_run_id: args.producer?.ci_run_id ?? "local",
      repo: args.producer?.repo ?? "unknown/unknown",
      commit: args.producer?.commit ?? "0".repeat(40)
    },
    row: {
      row_id: args.rowId,
      row_hash_id: ROW_HASH_ID,
      row_hash: args.rowHash,
      verification_policy_hash: args.verificationPolicyHash,
      approval_policy_hash: args.approvalPolicyHash
    },
    bindings: {
      binding_set_hash_id: BINDING_SET_HASH_ID,
      binding_set_hash: args.bindingSetHash,
      span_canon_id: SPAN_CANON_ID,
      items: args.bindings.map((binding) => ({
        binding_slug: binding.binding_slug,
        row_id: binding.row_id,
        file_path: binding.file_path,
        extent_kind: binding.extent_kind,
        recognizer_id: binding.recognizer_id,
        span_canon_id: binding.span_canon_id,
        span_sha256: binding.span.sha256,
        span_start_line: binding.span.start_line,
        span_end_line: binding.span.end_line
      }))
    },
    verification: {
      command_id: args.verification.command_id,
      result: "pass",
      started_at: args.verification.started_at,
      completed_at: args.verification.completed_at,
      artifacts: args.verification.artifacts,
      context_hash_id: VERIFICATION_CONTEXT_HASH_ID,
      context_hash: args.contextHash
    },
    entry_index: args.entryIndex,
    previous_entry_hash: args.previousEntryHash,
    // OPTIONAL: only embed the CI-neutral authority when one was supplied, so
    // proofs minted without it remain byte-for-byte as before (and legacy proofs
    // without it still validate + stay FRESH).
    ...(args.authority ? { authority: args.authority } : {})
  };
}
