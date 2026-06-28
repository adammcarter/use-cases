// Evidence ledger validation (spec section 5; Phase 5).
//
// The evidence ledger (`.use-cases/evidence.jsonl`) is an append-only log of
// signed, trusted-CI proof events (spec 5.1, amendment 3). This module turns the
// JSONL text into validated proof events and reports precise error codes for
// every way the ledger can be invalid:
//   - JSONL parse errors (with 1-based line numbers)
//   - proof-event schema failures (reuses the Phase 1 validator)
//   - producer / verification-result policy violations (spec 5.3 rules 4/5)
//   - signature failures (unsigned / unknown key / bad signature; spec 5.3)
//   - internal binding_set_hash inconsistency (spec 5.4 -> INVALID)
//   - non-append-only edits/deletes relative to a base ref (reuses Phase 3)
//
// Deliberately NOT done here (spec 5.4): comparing an event's embedded
// span_sha256 to the CURRENT scanned code. That drift is SUSPECT, not INVALID,
// and belongs to the Phase 6 freshness machine — never to validate-ledger.
//
// The core `validateEvidenceLedger` is pure (text in, result out). The only
// impure helper is a thin git base-ref read that reuses Phase 3's `readBaseRefFile`.
import { computeBindingSetHash } from "./bindingSetHash.js";
import { canonicalJsonSha256 } from "./canonicalJson.js";
import { validateProofEvent } from "./validators.js";
import {
  appendOnly,
  splitJsonlLines,
  readBaseRefFile,
  type ReadBaseRefOptions
} from "./appendOnly.js";
import { verifyEvent, type PublicKeyResolver } from "./proofSignature.js";

// One proof event (spec 5.2). Mirrors proof-event.schema.json.
export interface ProofBindingItem {
  binding_slug: string;
  row_id: string;
  file_path: string;
  extent_kind: string;
  recognizer_id: string;
  span_canon_id: string;
  span_sha256: string;
  span_start_line: number;
  span_end_line: number;
}

export interface ProofEvent {
  schema: string;
  event_type: string;
  event_id: string;
  created_at: string;
  producer: {
    kind: string;
    id: string;
    version: string;
    ci_run_id: string;
    repo: string;
    commit: string;
  };
  row: {
    row_id: string;
    row_hash_id: string;
    row_hash: string;
    verification_policy_hash: string;
    approval_policy_hash: string;
  };
  bindings: {
    binding_set_hash_id: string;
    binding_set_hash: string;
    span_canon_id: string;
    items: ProofBindingItem[];
  };
  verification: {
    command_id: string;
    result: string;
    started_at: string;
    completed_at: string;
    artifacts: Array<{ kind: string; path: string; sha256: string }>;
    // Binds the proof to its verifier context (policy + resolved verifier +
    // declared-input contents + lockfile). Re-derived at scan time; if it drifts
    // (e.g. the acceptance test was weakened), the proof is no longer FRESH.
    context_hash_id: string;
    context_hash: string;
  };
  signature: { alg: string; key_id: string; value: string };
  // --- Tamper-evident hash chain (v1, ADDITIVE / OPTIONAL) ---------------------
  // These two fields chain each entry to its predecessor so the ledger is
  // tamper-evident: removing or reordering an entry breaks the chain. They are
  // OPTIONAL because the committed ledger and many fixtures contain proof events
  // minted before the chain existed; those must still validate and stay FRESH.
  // When present (every freshly-proved entry), they are signed (built into the
  // event before signing), so they cannot be forged or altered after the fact.
  //
  // `entry_index`         — the entry's absolute 0-based position in the ledger.
  // `previous_entry_hash` — computeLedgerEntryHash of the immediately-preceding
  //                         entry, or GENESIS_ENTRY_HASH for the first entry.
  entry_index?: number;
  previous_entry_hash?: string;
}

// Genesis sentinel for `previous_entry_hash` on the first ledger entry. It is a
// well-formed "sha256:<hex>" string (64 zeros) so it satisfies the proof-event
// schema's hash pattern while being unmistakably the chain's root.
export const GENESIS_ENTRY_HASH = `sha256:${"0".repeat(64)}`;

// The canonical entry hash for the tamper-evident chain: sha256(canonicalJson)
// over the FULL signed proof event (signature and chain fields included). The
// next entry embeds this as its `previous_entry_hash`, so any edit to a prior
// entry — including its signature — invalidates every following link.
export function computeLedgerEntryHash(entry: unknown): string {
  return canonicalJsonSha256(entry);
}

// The trusted producer kind (spec 5.3 rule 4).
export const TRUSTED_CI_PRODUCER_KIND = "trusted-ci-prover";
// The only accepted verification result on an appended proof (spec 5.3 rule 5).
export const PROOF_PASS_RESULT = "pass";

// Stable error codes for every way the evidence ledger can be invalid
// (spec 5.3 / 5.4 / 7.1 and the section 11.4 evidence-laundering mutations).
export const EvidenceErrorCode = Object.freeze({
  JSON_PARSE_ERROR: "JSON_PARSE_ERROR",
  EVIDENCE_SCHEMA_INVALID: "EVIDENCE_SCHEMA_INVALID",
  SIGNATURE_MISSING: "SIGNATURE_MISSING",
  SIGNATURE_ALG_UNSUPPORTED: "SIGNATURE_ALG_UNSUPPORTED",
  UNKNOWN_KEY_ID: "UNKNOWN_KEY_ID",
  BAD_SIGNATURE: "BAD_SIGNATURE",
  PRODUCER_NOT_TRUSTED: "PRODUCER_NOT_TRUSTED",
  VERIFICATION_NOT_PASS: "VERIFICATION_NOT_PASS",
  BINDING_SET_HASH_MISMATCH: "BINDING_SET_HASH_MISMATCH",
  EVIDENCE_ROW_MISSING: "EVIDENCE_ROW_MISSING",
  APPEND_ONLY_VIOLATION: "APPEND_ONLY_VIOLATION"
} as const);

export type EvidenceErrorCode = (typeof EvidenceErrorCode)[keyof typeof EvidenceErrorCode];

export interface EvidenceError {
  code: EvidenceErrorCode;
  line: number | null; // 1-based source line, or null for ledger-level errors
  message: string;
  event_id?: string;
  row_id?: string;
}

// One raw parsed JSONL line (value is parsed-but-unvalidated JSON).
export interface EvidenceLine {
  line: number; // 1-based
  value: unknown;
}

export interface ReadEvidenceResult {
  lines: EvidenceLine[];
  errors: EvidenceError[]; // JSON_PARSE_ERROR entries only
}

// Read evidence JSONL text into one parsed value per line (spec 5.4 step "parse").
//
// A trailing newline is tolerated; whitespace-only lines are skipped so an empty
// or newline-terminated file reads cleanly. Any line that fails JSON.parse is
// reported as a JSON_PARSE_ERROR carrying its 1-based line number; remaining
// lines are still read.
export function readEvidenceJsonl(text: string): ReadEvidenceResult {
  const lines: EvidenceLine[] = [];
  const errors: EvidenceError[] = [];
  const rawLines = text.split("\n");
  for (let i = 0; i < rawLines.length; i += 1) {
    const raw = rawLines[i];
    if (raw.trim() === "") {
      continue; // tolerate trailing newline / blank separators
    }
    const lineNo = i + 1;
    try {
      lines.push({ line: lineNo, value: JSON.parse(raw) as unknown });
    } catch (error) {
      errors.push({
        code: EvidenceErrorCode.JSON_PARSE_ERROR,
        line: lineNo,
        message: `line ${lineNo} is not valid JSON: ${(error as Error).message}`
      });
    }
  }
  return { lines, errors };
}

// Safe path read of producer.kind / verification.result / event_id / row_id from
// an arbitrary parsed value, so policy checks can emit precise codes even when the
// shape is only partially correct.
function readPath(value: unknown, keys: string[]): unknown {
  let cursor: unknown = value;
  for (const key of keys) {
    if (typeof cursor !== "object" || cursor === null) {
      return undefined;
    }
    cursor = (cursor as Record<string, unknown>)[key];
  }
  return cursor;
}

export interface ValidateProofEventOptions {
  publicKeyResolver: PublicKeyResolver;
  yamlRowIds?: ReadonlySet<string>;
}

export interface ValidateProofEventResult {
  ok: boolean;
  errors: EvidenceError[];
  event: ProofEvent | null; // the typed event when every check passes
}

// Validate a single parsed proof-event value against every Phase 5 rule.
//
// Order: schema (structural gate) -> signature -> producer/result policy ->
// internal binding_set_hash recompute -> optional row existence. The signature,
// policy, and hash checks are defensive (guarded by path reads) so a precise code
// is still emitted even when the schema also rejects the value.
export function validateProofEventValue(
  value: unknown,
  line: number | null,
  options: ValidateProofEventOptions
): ValidateProofEventResult {
  const errors: EvidenceError[] = [];
  const eventId = readPath(value, ["event_id"]);
  const eventIdStr = typeof eventId === "string" ? eventId : undefined;
  const rowId = readPath(value, ["row", "row_id"]);
  const rowIdStr = typeof rowId === "string" ? rowId : undefined;

  // Structural gate: the Phase 1 proof-event schema (spec 5.2). The schema's
  // consts also enforce producer.kind and verification.result, but we still run
  // the dedicated policy checks below for precise, spec-named error codes.
  const schemaResult = validateProofEvent(value);
  const schemaOk = schemaResult.ok;
  if (!schemaOk) {
    errors.push({
      code: EvidenceErrorCode.EVIDENCE_SCHEMA_INVALID,
      line,
      message: `proof event failed schema: ${schemaResult.errors
        .map((e) => `${e.instance_path} ${e.message}`.trim())
        .join("; ")}`,
      event_id: eventIdStr,
      row_id: rowIdStr
    });
  }

  // Signature (spec 5.3 rules 1-3). verifyEvent reports the precise reason.
  const verifyResult = verifyEvent(value as Record<string, unknown>, options.publicKeyResolver);
  if (!verifyResult.ok) {
    errors.push({
      code: verifyResult.code,
      line,
      message: verifyResult.message,
      event_id: eventIdStr,
      row_id: rowIdStr
    });
  }

  // Producer must be trusted (spec 5.3 rule 4). Only emit the dedicated code when
  // the field is present-but-wrong; an absent producer is covered by the schema.
  const producerKind = readPath(value, ["producer", "kind"]);
  if (producerKind !== undefined && producerKind !== TRUSTED_CI_PRODUCER_KIND) {
    errors.push({
      code: EvidenceErrorCode.PRODUCER_NOT_TRUSTED,
      line,
      message: `producer.kind is ${String(producerKind)}; only ${TRUSTED_CI_PRODUCER_KIND} may mint proof events`,
      event_id: eventIdStr,
      row_id: rowIdStr
    });
  }

  // Verification result must be pass (spec 5.3 rules 5/6).
  const verificationResult = readPath(value, ["verification", "result"]);
  if (verificationResult !== undefined && verificationResult !== PROOF_PASS_RESULT) {
    errors.push({
      code: EvidenceErrorCode.VERIFICATION_NOT_PASS,
      line,
      message: `verification.result is ${String(verificationResult)}; only "${PROOF_PASS_RESULT}" proofs may be appended`,
      event_id: eventIdStr,
      row_id: rowIdStr
    });
  }

  // Internal binding_set_hash recompute (spec 5.4). The embedded
  // bindings.binding_set_hash must equal hash(bindings.items) for the row. A
  // mismatch is INVALID (internally inconsistent), distinct from SUSPECT drift.
  // Guarded by the schema so we only recompute over a well-formed bindings block.
  if (schemaOk) {
    const event = value as ProofEvent;
    // computeBindingSetHash whitelists hashed fields (spec 4.5), so the extra
    // diagnostic fields on each item (line numbers) are ignored. The cast adds
    // the index signature its input type expects.
    const recomputed = computeBindingSetHash(
      event.row.row_id,
      event.bindings.items as unknown as Array<Record<string, unknown> & ProofBindingItem>
    );
    if (recomputed !== event.bindings.binding_set_hash) {
      errors.push({
        code: EvidenceErrorCode.BINDING_SET_HASH_MISMATCH,
        line,
        message: `binding_set_hash ${event.bindings.binding_set_hash} does not recompute from items (got ${recomputed})`,
        event_id: eventIdStr,
        row_id: rowIdStr
      });
    }
    // Optional: proof event row id must exist (spec 5.4 validate-ledger step 10).
    if (options.yamlRowIds && !options.yamlRowIds.has(event.row.row_id)) {
      errors.push({
        code: EvidenceErrorCode.EVIDENCE_ROW_MISSING,
        line,
        message: `proof event row_id ${event.row.row_id} is not a known YAML row`,
        event_id: eventIdStr,
        row_id: event.row.row_id
      });
    }
  }

  const ok = errors.length === 0;
  return { ok, errors, event: ok ? (value as ProofEvent) : null };
}

export interface ValidateEvidenceLedgerOptions {
  publicKeyResolver: PublicKeyResolver;
  // Old evidence text at the base ref. When provided, the current ledger must be
  // an append-only superset of it (spec 5.4 / amendment 2; reuses Phase 3).
  baseRefOldText?: string;
  // When provided, each proof event's row_id must be a known YAML row.
  yamlRowIds?: ReadonlySet<string>;
}

export interface EvidenceLedgerSummary {
  proof_events_checked: number;
  proof_events_valid: number;
  proof_events_invalid: number;
  append_only: boolean;
  errors_by_code: Record<string, number>;
}

export interface ValidateEvidenceLedgerResult {
  ok: boolean;
  errors: EvidenceError[];
  events: ProofEvent[]; // events that passed every per-event rule, in order
  append_only: boolean;
  summary: EvidenceLedgerSummary;
}

// Validate a full evidence ledger: JSONL parse, proof-event schema, signature,
// producer/result policy, internal binding_set_hash recompute, optional row
// existence, and (when a base ref is supplied) append-only discipline.
//
// Pure: pass the current ledger text and the old base-ref text. Returns precise
// error codes plus a count summary. Does NOT compare embedded span hashes to
// current code (spec 5.4 "must not" — that is SUSPECT and Phase 6's job).
export function validateEvidenceLedger(
  text: string,
  options: ValidateEvidenceLedgerOptions
): ValidateEvidenceLedgerResult {
  const read = readEvidenceJsonl(text);
  const errors: EvidenceError[] = [...read.errors];
  const events: ProofEvent[] = [];

  // Append-only discipline relative to the base ref (spec 5.4 step 4). Reuses the
  // Phase 3 pure check; line-based so an edit or delete of any existing line is a
  // violation.
  let appendOnlyOk = true;
  if (options.baseRefOldText !== undefined) {
    const result = appendOnly(
      splitJsonlLines(options.baseRefOldText),
      splitJsonlLines(text)
    );
    if (!result.ok) {
      appendOnlyOk = false;
      errors.push({
        code: EvidenceErrorCode.APPEND_ONLY_VIOLATION,
        line: result.violation.index + 1,
        message: result.violation.message
      });
    }
  }

  let validCount = 0;
  for (const { line, value } of read.lines) {
    const result = validateProofEventValue(value, line, {
      publicKeyResolver: options.publicKeyResolver,
      yamlRowIds: options.yamlRowIds
    });
    if (result.ok && result.event) {
      events.push(result.event);
      validCount += 1;
    } else {
      errors.push(...result.errors);
    }
  }

  const errorsByCode: Record<string, number> = {};
  for (const error of errors) {
    errorsByCode[error.code] = (errorsByCode[error.code] ?? 0) + 1;
  }

  const checked = read.lines.length;
  const summary: EvidenceLedgerSummary = {
    proof_events_checked: checked,
    proof_events_valid: validCount,
    proof_events_invalid: checked - validCount,
    append_only: appendOnlyOk,
    errors_by_code: errorsByCode
  };

  return {
    ok: errors.length === 0,
    errors,
    events,
    append_only: appendOnlyOk,
    summary
  };
}

// Convenience: read the evidence file's base-ref version via git and validate the
// current text against it. Thin and impure — reuses Phase 3's `readBaseRefFile`
// (returns "" when the file is newly added at the base ref).
export function validateEvidenceLedgerAgainstBaseRef(
  text: string,
  baseRef: string,
  path: string,
  options: {
    publicKeyResolver: PublicKeyResolver;
    yamlRowIds?: ReadonlySet<string>;
  } & ReadBaseRefOptions
): ValidateEvidenceLedgerResult {
  const baseRefOldText = readBaseRefFile(baseRef, path, {
    cwd: options.cwd,
    runner: options.runner
  });
  return validateEvidenceLedger(text, {
    publicKeyResolver: options.publicKeyResolver,
    yamlRowIds: options.yamlRowIds,
    baseRefOldText
  });
}
