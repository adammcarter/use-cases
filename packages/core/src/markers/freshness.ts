// Freshness state machine (spec sections 6, 7, 10.2; Phase 6).
//
// `deriveFreshness` is the pure integration point that ties Phases 1-5 together:
// it consumes loaded rows, the materialized registry (P3), the current scan
// (P2/P4), and the already-validated trusted proof events (P5), and derives one
// status per row IN THE SPEC'S ORDER (7.1 INVALID -> 7.2 UNBOUND -> 7.3 SUSPECT
// removed -> 7.4 UNPROVEN -> 7.5 FRESH -> 7.6 SUSPECT stale), then applies the
// policy gate (10.2). The emitted object matches spec section 6 and validates
// against the Phase 1 `ucase-freshness-status-v1` schema.
//
// Pure core: no Date.now (the timestamp is injected), no filesystem, no git. All
// inputs are hand-buildable, so the whole machine is unit-testable in isolation.
import { computeRowHash } from "./rowHash.js";
import {
  computeApprovalPolicyHash,
  computeVerificationPolicyHash
} from "./policyHash.js";
import { computeBindingSetHash } from "./bindingSetHash.js";
import { reconcileRegistryWithScan, type RowReconciliation } from "./reconcile.js";
import { splitSlug } from "./markerLine.js";
import { SPAN_CANON_ID, STATUS_SCHEMA_ID } from "./constants.js";
import { PRODUCT_NAME, UCM_VERSION } from "../version.js";
import { PROOF_PASS_RESULT, type ProofEvent } from "./evidenceLedger.js";
import type { CiAuthority } from "./ciAuthority.js";
import type { MaterializedRegistry } from "./registry.js";
import type { CurrentBindingRecord, MarkerError, ScanResult } from "./scanner.js";

export type RowStatus = "FRESH" | "SUSPECT" | "UNPROVEN" | "UNBOUND" | "INVALID";
export type PolicyMode = "feature" | "release" | "custom";

// Keyless, unsigned local-verification tier (0.1.0). Reported IN PARALLEL with
// the signed `status`, never in place of it. Derived from the UNSIGNED
// verification-results ledger (what `verify --out` writes), so it needs no keys:
//   VERIFIED_LOCAL   bound row with a passing unsigned result whose context +
//                    binding set still match the current code/test — the keyless
//                    analogue of FRESH.
//   STALE_LOCAL      a result exists but its context/binding set no longer match,
//                    or the recorded result was a failure — the analogue of SUSPECT.
//   UNVERIFIED_LOCAL bound row with no local result yet.
//   null             UNBOUND / INVALID (nothing to locally verify).
export type LocalStatus = "VERIFIED_LOCAL" | "STALE_LOCAL" | "UNVERIFIED_LOCAL";

// One row's UNSIGNED verification result, distilled from the results ledger
// (`ucase-verification-result-v1`). `context_hash` mirrors the record's
// `verification_context_hash` and `binding_set_hash` its `binding_set_hash`, so
// `local_status` can apply the SAME context + hBind match FRESH uses — keylessly.
export interface LocalVerificationResult {
  row_id: string;
  context_hash: string;
  binding_set_hash: string;
  passed: boolean;
}

// A loaded use-case row. `computeRowHash` hashes the whole object (Hrow), so any
// semantic edit changes the row hash; the two policy sub-objects feed Hverify /
// Happrove via the Phase 1 policy-hash helpers.
export interface FreshnessInputRow {
  row_id: string;
  verification_policy: unknown;
  approval_policy: unknown;
  [key: string]: unknown;
}

// Context handed to a custom policy predicate (spec 10.2 "custom").
export interface PolicyDecisionContext {
  row_id: string;
  status: RowStatus;
  required_for_release: boolean;
  is_invalid: boolean;
}

export type CustomPolicyPredicate = (context: PolicyDecisionContext) => boolean;

// CI-neutral release-gate AUTHORITY requirement (public-v1, Phase 2, Piece 2).
//
// OPTIONAL / off by default. When configured, a `required_for_release` row whose
// matching FRESH proof was minted with insufficient provenance authority is
// POLICY-BLOCKED in RELEASE mode (and only release mode). The check is purely
// ADDITIVE: it can only ever block an otherwise-FRESH required row; it never
// relaxes the existing "required + not FRESH" block, and it never touches
// feature/custom mode. The trust model is CI-NEUTRAL — the proof's `authority`
// block (mirrors authority.schema.json) records WHO/WHERE minted it, regardless
// of provider (GitHub Actions is only the reference). When nothing is configured
// (the whole object omitted, empty, or every field falsy) behaviour is exactly
// as before.
export interface ReleaseGatePolicy {
  // When "ci", the matching proof's `authority.type` must be "ci" (i.e. minted
  // inside a recognised CI provider, not a local run). Any other value (or an
  // absent authority block) is insufficient.
  required_authority?: "ci";
  // When true, the matching proof's `authority.protected_ref` must be exactly
  // `true` (the provider attested the ref is a protected branch). `false` or
  // `null` (unknown) — or an absent authority block — is insufficient.
  require_protected_ref?: boolean;
}

export interface DeriveFreshnessInput {
  // R: the loaded YAML rows.
  rows: ReadonlyArray<FreshnessInputRow>;
  // Materialized append-only binding registry (P3): row -> registered slugs.
  registry: MaterializedRegistry;
  // Current scan (P2/P4): current binding records + binding-integrity errors.
  scan: ScanResult;
  // Already signature/schema-validated trusted passing proof events (P5).
  evidence: ReadonlyArray<ProofEvent>;
  policy_mode: PolicyMode;
  // Only consulted when policy_mode === "custom".
  custom_policy?: CustomPolicyPredicate;
  // OPTIONAL CI-neutral release-gate authority requirement. Only consulted in
  // RELEASE mode; off by default (omit / empty => no change to today's gating).
  release_gate?: ReleaseGatePolicy;
  // Freshly recomputed verification context hash per row (rowId -> sha), derived
  // by scan from the CURRENT resolved verifier + declared-input contents. When
  // provided, a proof is only FRESH if its embedded verification.context_hash
  // equals the row's recomputed value — so weakening/deleting the row's
  // acceptance test (which changes this hash) drops the row out of FRESH even
  // when the production spans are untouched. Omitted only by pure unit callers
  // that do not exercise the context binding; scan/prove always supply it.
  current_context_hashes?: ReadonlyMap<string, string>;
  // OPTIONAL unsigned verification results (what `verify --out` writes), one per
  // row. When supplied, `deriveFreshness` computes a parallel keyless
  // `local_status` per row. Omitted => no `local_status` is emitted (existing
  // callers are byte-identical). Never affects the signed `status`.
  local_results?: ReadonlyArray<LocalVerificationResult>;
  // Injected so the core stays pure and deterministic (no Date.now).
  generated_at: string;
  product_root?: string;
  tool?: { name: string; version: string };
  // Optional ledger/registry-level integrity errors (e.g. validate-ledger
  // failures) that are not tied to a single row. They flip guard_ok to false.
  global_integrity_errors?: ReadonlyArray<Record<string, unknown>>;
}

export interface FreshnessReason {
  code: string;
  binding_slug?: string;
  expected_span_sha256?: string;
  actual_span_sha256?: string;
  expected_file_path?: string;
  actual_file_path?: string;
  message?: string;
}

export interface ProofRef {
  event_id: string;
  created_at: string;
  commit: string;
}

export interface CurrentBindingOut {
  binding_slug: string;
  file_path: string;
  extent_kind: "explicit" | "swift_func_inferred";
  recognizer_id: string;
  span_canon_id: string;
  span_sha256: string;
  span_start_line: number;
  span_end_line: number;
}

export interface IntegrityErrorOut {
  code: string;
  row_id?: string;
  binding_slug?: string;
  file_path?: string;
  line?: number;
  message?: string;
  // The runnable way OUT. Integrity messages described the wreckage
  // ("marker X is not registered") but never the cure, leaving the reader to
  // work out a fix the tool already knew. Every error class that HAS a
  // mechanical remedy now carries it.
  remediation?: string;
}

export interface FreshnessRowOut {
  row_id: string;
  row_hash?: string;
  verification_policy_hash?: string;
  approval_policy_hash?: string;
  status: RowStatus;
  policy_block: boolean;
  reasons: FreshnessReason[];
  known_binding_slugs: string[];
  current_binding_slugs: string[];
  missing_registered_binding_slugs: string[];
  unregistered_current_binding_slugs: string[];
  current_binding_set_hash?: string;
  current_bindings: CurrentBindingOut[];
  matching_proof_event: ProofRef | null;
  latest_trusted_proof_event: ProofRef | null;
  required_action: string | null;
  // Whether this row is marked `required_for_release` in its approval policy.
  // Surfaced (0.1.0) so `scan --gate` can gate purely on required rows without
  // re-reading the approval policy. Additive: never affects the headline status.
  required_for_release?: boolean;
  // Keyless local-verification tier (0.1.0). Present only when the caller
  // supplied `local_results`; null/absent for UNBOUND/INVALID rows. Additive:
  // never changes the headline `status`.
  local_status?: LocalStatus | null;
  local_reason?: string | null;
  // For a variant family only: the per-variant keyless local status breakdown, in
  // stable key order. The family's own `local_status` is VERIFIED_LOCAL iff every
  // entry here is VERIFIED_LOCAL. Additive/optional — absent for ordinary rows.
  variant_local_status?: Array<{ key: string; local_status: LocalStatus }>;
}

export interface FreshnessSummary {
  fresh: number;
  suspect: number;
  unproven: number;
  unbound: number;
  invalid: number;
  policy_blocked: number;
  // The KEYLESS LOCAL axis. The four counts above describe the *signed* tier,
  // which is UNPROVEN by design on every local run — so a fully green keyless
  // matrix still reported `fresh: 0, unproven: N` and read like a disaster.
  // These count the axis the daily loop actually gates on.
  verified_local: number;
  stale_local: number;
  unverified_local: number;
}

// The acceptance conclusion, stated outright.
//
// `guard_ok` answers a narrower question than its name suggests ("is any policy
// blocking?"), and reads `true` on a matrix where nothing is proven at all. It
// keeps that meaning — CI gates depend on it — so this states the claim that
// `guard_ok` does not: how many behaviours are actually proven, and whether
// acceptance can honestly be claimed. Agents quote conclusions; give them a true one.
export interface AcceptanceClaim {
  // Rows proven by EITHER tier: a signed FRESH proof, or a current VERIFIED_LOCAL run.
  proven: number;
  total: number;
  claimable: boolean;
  statement: string;
}

export interface FreshnessStatus {
  schema: typeof STATUS_SCHEMA_ID;
  generated_at: string;
  tool: { name: string; version: string };
  product_root: string;
  policy_mode: PolicyMode;
  guard_ok: boolean;
  acceptance_claim: AcceptanceClaim;
  summary: FreshnessSummary;
  integrity_errors: IntegrityErrorOut[];
  rows: FreshnessRowOut[];
}

const DEFAULT_TOOL = { name: PRODUCT_NAME, version: UCM_VERSION };

// A rename is only suggested well above chance similarity. Tuned so that a real
// rename (mcp_whiteboard -> mcp_stage, which shares its whole namespace prefix)
// is caught, while an unrelated new row in a different feature is not.
const RENAME_SIMILARITY_THRESHOLD = 0.6;

// Sørensen–Dice over character bigrams: cheap, no dependency, and forgiving of
// the insert/delete edits a rename actually makes.
function bigrams(value: string): Map<string, number> {
  const counts = new Map<string, number>();
  for (let index = 0; index < value.length - 1; index += 1) {
    const gram = value.slice(index, index + 2);
    counts.set(gram, (counts.get(gram) ?? 0) + 1);
  }
  return counts;
}

function similarity(left: string, right: string): number {
  if (left === right) {
    return 1;
  }
  const leftGrams = bigrams(left);
  const rightGrams = bigrams(right);
  let shared = 0;
  for (const [gram, count] of leftGrams) {
    shared += Math.min(count, rightGrams.get(gram) ?? 0);
  }
  const total = [...leftGrams.values()].reduce((sum, n) => sum + n, 0) +
    [...rightGrams.values()].reduce((sum, n) => sum + n, 0);
  return total === 0 ? 0 : (2 * shared) / total;
}

// Map each unregistered binding slug -> the row id it was most likely renamed
// FROM. Conservative on purpose: a candidate must clear the threshold AND be
// strictly better than every other candidate. An ambiguous rename says nothing,
// because a confidently wrong suggestion is worse than none.
//: @use-case:lifecycle.signals.errors_hand_back_the_cure
function inferRenames(
  unregistered: { binding_slug: string; row_id: string }[],
  missing: { binding_slug: string; row_id: string }[]
): Map<string, string> {
  const result = new Map<string, string>();
  if (missing.length === 0) {
    return result;
  }

  for (const detection of unregistered) {
    const scored = missing
      .map((candidate) => ({
        rowId: candidate.row_id,
        score: similarity(detection.row_id, candidate.row_id)
      }))
      .filter((candidate) => candidate.score >= RENAME_SIMILARITY_THRESHOLD)
      .sort((left, right) => right.score - left.score);

    if (scored.length === 0) {
      continue;
    }
    // Ambiguous: two candidates fit equally well. Refuse to guess.
    if (scored.length > 1 && scored[0].score === scored[1].score) {
      continue;
    }
    result.set(detection.binding_slug, scored[0].rowId);
  }
  return result;
}
//: @use-case:end lifecycle.signals.errors_hand_back_the_cure

function rowIdOfSlug(slug: string | undefined): string | undefined {
  if (slug === undefined) {
    return undefined;
  }
  const parts = splitSlug(slug);
  return parts ? parts.row_id : slug;
}

function proofRef(event: ProofEvent): ProofRef {
  return {
    event_id: event.event_id,
    created_at: event.created_at,
    commit: event.producer.commit
  };
}

// Newest-first by created_at (ISO timestamps sort lexically), stable otherwise.
function byNewest(events: ProofEvent[]): ProofEvent[] {
  return [...events].sort((left, right) => {
    if (left.created_at < right.created_at) {
      return 1;
    }
    if (left.created_at > right.created_at) {
      return -1;
    }
    return 0;
  });
}

function requiredForRelease(approvalPolicy: unknown): boolean {
  return (
    typeof approvalPolicy === "object" &&
    approvalPolicy !== null &&
    (approvalPolicy as Record<string, unknown>).required_for_release === true
  );
}

function trustedProducer(approvalPolicy: unknown): string | undefined {
  if (typeof approvalPolicy !== "object" || approvalPolicy === null) {
    return undefined;
  }
  const value = (approvalPolicy as Record<string, unknown>).trusted_producer;
  return typeof value === "string" ? value : undefined;
}

// Spec 7.5: "current approval policy accepts proof.producer and proof.verification".
function approvalAcceptsProof(approvalPolicy: unknown, proof: ProofEvent): boolean {
  if (proof.verification.result !== PROOF_PASS_RESULT) {
    return false;
  }
  const expectedProducer = trustedProducer(approvalPolicy);
  if (expectedProducer !== undefined && proof.producer.kind !== expectedProducer) {
    return false;
  }
  return true;
}

function bindingToOut(binding: CurrentBindingRecord): CurrentBindingOut {
  return {
    binding_slug: binding.binding_slug,
    file_path: binding.file_path,
    extent_kind: binding.extent_kind,
    recognizer_id: binding.recognizer_id,
    span_canon_id: binding.span_canon_id,
    span_sha256: binding.span.sha256,
    span_start_line: binding.span.start_line,
    span_end_line: binding.span.end_line
  };
}

function bindingToSetMember(binding: CurrentBindingRecord) {
  return {
    binding_slug: binding.binding_slug,
    row_id: binding.row_id,
    file_path: binding.file_path,
    extent_kind: binding.extent_kind,
    recognizer_id: binding.recognizer_id,
    span_canon_id: binding.span_canon_id,
    span_sha256: binding.span.sha256
  };
}

// Spec 7.6: derive the stale-proof reason codes against the LATEST proof event.
function deriveStaleReasons(
  latest: ProofEvent | undefined,
  hRow: string,
  hVerify: string,
  hApprove: string,
  hBind: string,
  current: CurrentBindingRecord[],
  // The freshly recomputed verification context hash, or undefined when the
  // caller did not supply context hashes (then this drift is not checked).
  currentContextHash?: string
): FreshnessReason[] {
  const reasons: FreshnessReason[] = [];
  if (!latest) {
    reasons.push({ code: "NO_MATCHING_TRUSTED_PROOF" });
    return reasons;
  }

  if (currentContextHash !== undefined && latest.verification.context_hash !== currentContextHash) {
    reasons.push({
      code: "VERIFICATION_CONTEXT_CHANGED",
      message: `verification context changed since proof (${latest.verification.context_hash} -> ${currentContextHash}); the verifier or its declared inputs were modified`
    });
  }

  if (latest.row.row_hash !== hRow) {
    reasons.push({
      code: "ROW_HASH_CHANGED",
      message: `row hash changed since proof (${latest.row.row_hash} -> ${hRow})`
    });
  }
  if (latest.row.verification_policy_hash !== hVerify) {
    reasons.push({
      code: "VERIFICATION_POLICY_CHANGED",
      message: `verification policy changed since proof (${latest.row.verification_policy_hash} -> ${hVerify})`
    });
  }
  if (latest.row.approval_policy_hash !== hApprove) {
    reasons.push({
      code: "APPROVAL_POLICY_CHANGED",
      message: `approval policy changed since proof (${latest.row.approval_policy_hash} -> ${hApprove})`
    });
  }

  const proofItems = new Map(latest.bindings.items.map((item) => [item.binding_slug, item]));
  const currentBySlug = new Map(current.map((binding) => [binding.binding_slug, binding]));
  let bindingSpecificReason = false;

  // Per-slug comparisons for slugs present in both proof and current scan.
  for (const binding of current) {
    const item = proofItems.get(binding.binding_slug);
    if (!item) {
      reasons.push({ code: "BINDING_ADDED", binding_slug: binding.binding_slug });
      bindingSpecificReason = true;
      continue;
    }
    if (item.file_path !== binding.file_path) {
      reasons.push({
        code: "BINDING_PATH_CHANGED",
        binding_slug: binding.binding_slug,
        expected_file_path: item.file_path,
        actual_file_path: binding.file_path
      });
      bindingSpecificReason = true;
    }
    if (item.span_sha256 !== binding.span.sha256) {
      reasons.push({
        code: "CODE_SPAN_CHANGED",
        binding_slug: binding.binding_slug,
        expected_span_sha256: item.span_sha256,
        actual_span_sha256: binding.span.sha256
      });
      bindingSpecificReason = true;
    }
    if (item.span_canon_id !== binding.span_canon_id) {
      reasons.push({
        code: "CANON_CHANGED",
        binding_slug: binding.binding_slug,
        message: `span canon changed (${item.span_canon_id} -> ${binding.span_canon_id})`
      });
      bindingSpecificReason = true;
    }
  }

  // Slugs in the proof but no longer present in the current scan.
  for (const item of latest.bindings.items) {
    if (!currentBySlug.has(item.binding_slug)) {
      reasons.push({ code: "BINDING_REMOVED", binding_slug: item.binding_slug });
      bindingSpecificReason = true;
    }
  }

  // Whole-set hash drift with no more specific binding reason: report the
  // generic BINDING_SET_CHANGED so the drift is never silent.
  if (!bindingSpecificReason && latest.bindings.binding_set_hash !== hBind) {
    reasons.push({
      code: "BINDING_SET_CHANGED",
      message: `binding set hash changed since proof (${latest.bindings.binding_set_hash} -> ${hBind})`
    });
  }

  // No drift explained the staleness (e.g. proof rejected by approval policy or
  // an unsupported canon): fall back to the catch-all reason.
  if (reasons.length === 0) {
    reasons.push({ code: "NO_MATCHING_TRUSTED_PROOF" });
  }
  return reasons;
}

// Is any authority requirement actually configured? An omitted, empty, or
// all-falsy `release_gate` means "no requirement" — behaviour stays as today.
function authorityGateActive(policy: ReleaseGatePolicy | undefined): boolean {
  if (!policy) {
    return false;
  }
  return policy.required_authority === "ci" || policy.require_protected_ref === true;
}

// Does the matching proof's authority satisfy the configured release-gate
// requirement? CI-neutral: only the authority shape is inspected (not the
// provider). An absent authority block satisfies nothing once a requirement is
// active. Returns true when no requirement is configured.
function authoritySatisfies(
  policy: ReleaseGatePolicy | undefined,
  authority: CiAuthority | undefined
): boolean {
  if (!authorityGateActive(policy)) {
    return true;
  }
  if (policy?.required_authority === "ci" && authority?.type !== "ci") {
    return false;
  }
  if (policy?.require_protected_ref === true && authority?.protected_ref !== true) {
    return false;
  }
  return true;
}

// Human-readable explanation for an AUTHORITY_INSUFFICIENT block.
function authorityReason(
  policy: ReleaseGatePolicy | undefined,
  authority: CiAuthority | undefined
): string {
  const wants: string[] = [];
  if (policy?.required_authority === "ci") {
    wants.push('authority.type === "ci"');
  }
  if (policy?.require_protected_ref === true) {
    wants.push("authority.protected_ref === true");
  }
  const got = authority
    ? `type=${authority.type}, protected_ref=${String(authority.protected_ref ?? null)}`
    : "no authority block on the matching proof";
  return `release gate requires ${wants.join(" and ")}, but the matching proof has ${got}`;
}

function evaluatePolicyBlock(
  mode: PolicyMode,
  status: RowStatus,
  required: boolean,
  rowId: string,
  custom: CustomPolicyPredicate | undefined,
  // True when an active release-gate authority requirement is NOT met by the
  // matching FRESH proof for a required row. Only meaningful in release mode.
  authorityInsufficient: boolean
): boolean {
  const isInvalid = status === "INVALID";
  if (mode === "feature") {
    return isInvalid; // feature blocks only INVALID (spec 10.2 / 8.2)
  }
  if (mode === "release") {
    // release blocks INVALID and any required row that is not FRESH (spec 10.2).
    // ADDITIVE: a required row that IS FRESH is also blocked when its matching
    // proof's provenance authority falls short of the configured requirement.
    return (
      isInvalid ||
      (required && status !== "FRESH") ||
      (required && status === "FRESH" && authorityInsufficient)
    );
  }
  // custom: defer to the configured predicate; default to feature behaviour.
  if (custom) {
    return custom({ row_id: rowId, status, required_for_release: required, is_invalid: isInvalid });
  }
  return isInvalid;
}

// Keyless local tier for ONE bound row. `results` are the row's unsigned
// verification results; `currentContextHash`/`hBind` are the row's freshly
// recomputed values. A passing result whose context AND binding set both still
// match => VERIFIED_LOCAL; a result that exists but no longer matches (or was a
// failure) => STALE_LOCAL; no result => UNVERIFIED_LOCAL. Pure + side-effect free.
function deriveLocalStatus(
  results: LocalVerificationResult[],
  currentContextHash: string | undefined,
  hBind: string
): { local_status: LocalStatus; local_reason: string | null } {
  if (results.length === 0) {
    return { local_status: "UNVERIFIED_LOCAL", local_reason: null };
  }
  const passing = results.some(
    (result) =>
      result.passed &&
      result.binding_set_hash === hBind &&
      (currentContextHash === undefined || result.context_hash === currentContextHash)
  );
  if (passing) {
    return { local_status: "VERIFIED_LOCAL", local_reason: null };
  }
  // A result exists but none currently matches: explain the drift (analogue of
  // SUSPECT). Prefer the most specific reason from the newest-considered result.
  const anyFailure = results.some((result) => !result.passed);
  const contextDrifted = results.some(
    (result) =>
      result.passed &&
      currentContextHash !== undefined &&
      result.context_hash !== currentContextHash
  );
  const bindingDrifted = results.some(
    (result) => result.passed && result.binding_set_hash !== hBind
  );
  let reason: string;
  if (contextDrifted) {
    reason =
      "the verifier or its declared inputs changed since the last local run; re-run `uc verify`";
  } else if (bindingDrifted) {
    reason = "the bound code span changed since the last local run; re-run `uc verify`";
  } else if (anyFailure) {
    reason = "the last local verification did not pass; fix the row and re-run `uc verify`";
  } else {
    reason = "the last local verification no longer matches the current row; re-run `uc verify`";
  }
  return { local_status: "STALE_LOCAL", local_reason: reason };
}

export function deriveFreshness(input: DeriveFreshnessInput): FreshnessStatus {
  const reconciliation = reconcileRegistryWithScan(input.registry, input.scan);
  const reconByRow = new Map<string, RowReconciliation>();
  for (const recon of reconciliation.rows) {
    reconByRow.set(recon.row_id, recon);
  }

  // Index the scan by row id (all current marker records for the row).
  const bindingsByRow = new Map<string, CurrentBindingRecord[]>();
  for (const binding of input.scan.bindings) {
    const list = bindingsByRow.get(binding.row_id) ?? [];
    list.push(binding);
    bindingsByRow.set(binding.row_id, list);
  }

  // Per-row binding-integrity errors derived from the scan (malformed marker,
  // forbidden payload, duplicate slug, end/nesting/mismatch, unsupported
  // inference, ...). Errors with no resolvable slug become global.
  const scanErrorsByRow = new Map<string, MarkerError[]>();
  const globalIntegrity: IntegrityErrorOut[] = [
    ...(input.global_integrity_errors ?? []).map(
      (raw) => ({ code: "LEDGER_INTEGRITY_ERROR", ...raw }) as IntegrityErrorOut
    )
  ];
  for (const error of input.scan.errors) {
    const rowId = rowIdOfSlug(error.slug);
    if (rowId === undefined) {
      globalIntegrity.push({
        code: error.code,
        file_path: error.file_path,
        line: error.line,
        message: error.message
      });
      continue;
    }
    const list = scanErrorsByRow.get(rowId) ?? [];
    list.push(error);
    scanErrorsByRow.set(rowId, list);
  }

  // Unregistered current markers -> INVALID (spec 7.1), keyed by row.
  const unregisteredByRow = new Map<string, typeof reconciliation.unregistered>();
  for (const detection of reconciliation.unregistered) {
    const list = unregisteredByRow.get(detection.row_id) ?? [];
    list.push(detection);
    unregisteredByRow.set(detection.row_id, list);
  }

  // Likely renames. A rename leaves two halves the tool can already see: the OLD
  // row, which no longer exists, and an UNREGISTERED marker carrying a
  // near-identical NEW id. Pair them so the error names the cause instead of only
  // the wreckage. Advisory: changes no status and no trust verdict — remediation
  // text only.
  //
  // The old half arrives by TWO routes, and a real rename uses the second:
  //   - reconciliation.missing — the row still exists in YAML but its marker is gone.
  //   - REGISTRY_ROW_MISSING   — the row id is no longer in YAML at all, so registry
  //     materialization rejects its binding outright and it never reaches the
  //     registry map. Renaming a row in the matrix lands here, NOT in `missing`.
  const orphanedRegistryRows = globalIntegrity
    .filter((error) => error.code === "REGISTRY_ROW_MISSING" && error.row_id)
    .map((error) => ({ binding_slug: error.binding_slug ?? "", row_id: error.row_id as string }));
  const renamedFrom = inferRenames(reconciliation.unregistered, [
    ...reconciliation.missing,
    ...orphanedRegistryRows
  ]);

  // The reverse view: old row id -> the new id it was probably renamed TO. This is
  // what the OLD half of the rename (REGISTRY_ROW_MISSING) needs to explain itself.
  const renamedTo = new Map<string, string>();
  for (const [bindingSlug, previousRowId] of renamedFrom) {
    const detection = reconciliation.unregistered.find(
      (entry) => entry.binding_slug === bindingSlug
    );
    if (detection) {
      renamedTo.set(previousRowId, detection.row_id);
    }
  }

  // Give each global error the cure for ITS code, not a blanket one.
  for (const error of globalIntegrity) {
    if (error.remediation) {
      continue;
    }
    if (error.code === "REGISTRY_ROW_MISSING") {
      const newRowId = error.row_id ? renamedTo.get(error.row_id) : undefined;
      // Tell the truth about the cure. The registry is append-only and has NO
      // retract event, so the stale registration cannot be superseded — and
      // `uc bind` validates the registry first, so it fails closed on this very
      // error. The only sequence that actually works today is: drop the stale
      // line, then re-register. Verified end-to-end; do not "simplify" this to a
      // bare `uc bind`, which cannot succeed while this error stands.
      error.remediation = newRowId
        ? `looks like ${error.row_id} was renamed to ${newRowId}. The binding registry is ` +
          `append-only with no retract event, so \`uc bind\` will fail closed until the stale ` +
          `registration is gone: delete the ${error.row_id} line from .use-cases/bindings.jsonl, ` +
          `then run \`uc bind --row ${newRowId} --file <file> --register-existing\``
        : `the registry still binds ${error.row_id ?? "a row"}, which no longer exists in the ` +
          `matrix. Restore the row to the matrix, or delete its line from ` +
          `.use-cases/bindings.jsonl and re-register the binding against the row that replaced it`;
    } else if (error.code === "LEDGER_INTEGRITY_ERROR") {
      error.remediation =
        "inspect the ledger with `uc validate-ledger` — a proof/binding ledger entry is malformed or out of order";
    }
  }

  // Trusted passing proof events grouped by row (newest first).
  const evidenceByRow = new Map<string, ProofEvent[]>();
  for (const event of input.evidence) {
    const list = evidenceByRow.get(event.row.row_id) ?? [];
    list.push(event);
    evidenceByRow.set(event.row.row_id, list);
  }
  for (const [rowId, events] of evidenceByRow) {
    evidenceByRow.set(rowId, byNewest(events));
  }

  // Unsigned local verification results grouped by row (keyless tier). Only
  // consulted when the caller supplied them; omission leaves local_status absent.
  const localResultsProvided = input.local_results !== undefined;
  const localResultsByRow = new Map<string, LocalVerificationResult[]>();
  for (const result of input.local_results ?? []) {
    const list = localResultsByRow.get(result.row_id) ?? [];
    list.push(result);
    localResultsByRow.set(result.row_id, list);
  }

  // Index the loaded rows; the row set is the union of loaded rows and any row
  // referenced by the registry/scan/errors, so nothing silently vanishes.
  const rowById = new Map<string, FreshnessInputRow>();
  for (const row of input.rows) {
    rowById.set(row.row_id, row);
  }
  const rowIds = new Set<string>();
  for (const row of input.rows) {
    rowIds.add(row.row_id);
  }
  for (const recon of reconciliation.rows) {
    rowIds.add(recon.row_id);
  }
  for (const rowId of scanErrorsByRow.keys()) {
    rowIds.add(rowId);
  }

  const outRows: FreshnessRowOut[] = [];
  const allIntegrity: IntegrityErrorOut[] = [...globalIntegrity];
  const summary: FreshnessSummary = {
    fresh: 0,
    suspect: 0,
    unproven: 0,
    unbound: 0,
    invalid: 0,
    policy_blocked: 0,
    verified_local: 0,
    stale_local: 0,
    unverified_local: 0
  };
  // A row is PROVEN if either tier vouches for it: a signed FRESH proof, or a
  // current passing local run. This is what acceptance is actually claimed on.
  let provenRows = 0;

  for (const rowId of [...rowIds].sort()) {
    const inputRow = rowById.get(rowId);
    const recon = reconByRow.get(rowId);
    const knownSlugs = recon?.registered_binding_slugs ?? [];
    const currentSlugs = recon?.current_binding_slugs ?? [];
    const missingSlugs = recon?.missing_registered_binding_slugs ?? [];
    const unregisteredSlugs = recon?.unregistered_current_binding_slugs ?? [];

    // C(row): current, valid, REGISTERED binding records for the row.
    const knownSet = new Set(knownSlugs);
    const allCurrent = bindingsByRow.get(rowId) ?? [];
    const currentRegistered = allCurrent.filter((binding) => knownSet.has(binding.binding_slug));

    // Assemble this row's integrity errors (spec 7.1).
    const rowIntegrity: IntegrityErrorOut[] = [];
    for (const error of scanErrorsByRow.get(rowId) ?? []) {
      rowIntegrity.push({
        code: error.code,
        row_id: rowId,
        binding_slug: error.slug,
        file_path: error.file_path,
        line: error.line,
        message: error.message
      });
    }
    for (const detection of unregisteredByRow.get(rowId) ?? []) {
      const previousId = renamedFrom.get(detection.binding_slug);
      rowIntegrity.push({
        code: "UNREGISTERED_BINDING",
        row_id: rowId,
        binding_slug: detection.binding_slug,
        file_path: detection.file_path,
        line: detection.start_line,
        message: `current marker ${detection.binding_slug} is not registered in the binding registry`,
        remediation: previousId
          ? `looks like ${rowId} was renamed from ${previousId}. Delete the ${previousId} line ` +
            `from .use-cases/bindings.jsonl (the registry is append-only and cannot retract it, ` +
            `so bind fails closed until it is gone), then run ` +
            `\`uc bind --row ${rowId} --file ${detection.file_path} --register-existing\``
          : `register the marker already in the source with ` +
            `\`uc bind --row ${rowId} --file ${detection.file_path} --register-existing\`` +
            `, or delete the marker if it is not wanted`
      });
    }
    if (!inputRow) {
      // A marker/registry references a row that does not exist in the loaded
      // rows (spec 7.1 "marker row id does not exist" / "registry row id does
      // not exist").
      const renamedSlug = (unregisteredByRow.get(rowId) ?? []).find((detection) =>
        renamedFrom.has(detection.binding_slug)
      );
      const previousId = renamedSlug ? renamedFrom.get(renamedSlug.binding_slug) : undefined;
      rowIntegrity.push({
        code: "ROW_NOT_FOUND",
        row_id: rowId,
        message: `row ${rowId} is bound or registered but is not a known use-case row`,
        remediation: previousId
          ? `looks like ${previousId} was renamed to ${rowId} — add the renamed row to the ` +
            `matrix (or rename it back), then re-register with ` +
            `\`uc bind --row ${rowId} --file <file> --register-existing\``
          : `add the row to the matrix, or — if the row id was RENAMED — update the ` +
            `\`@use-case:\` marker(s) in source to the new id and re-register with ` +
            `\`uc bind --row <new-id> --file <file> --register-existing\``
      });
    }

    const hashes = inputRow
      ? {
          row_hash: computeRowHash(inputRow),
          verification_policy_hash: computeVerificationPolicyHash(inputRow.verification_policy),
          approval_policy_hash: computeApprovalPolicyHash(inputRow.approval_policy)
        }
      : undefined;
    const hBind = computeBindingSetHash(rowId, currentRegistered.map(bindingToSetMember));
    const proofs = evidenceByRow.get(rowId) ?? [];
    const latestProof = proofs[0];

    // -- Status derivation IN SPEC ORDER (7.1 -> 7.6) --
    let status: RowStatus;
    let reasons: FreshnessReason[] = [];
    let matching: ProofEvent | undefined;

    if (rowIntegrity.length > 0) {
      // 7.1 INVALID
      status = "INVALID";
      reasons = rowIntegrity.map((error) => ({
        code: error.code,
        ...(error.binding_slug ? { binding_slug: error.binding_slug } : {}),
        ...(error.message ? { message: error.message } : {})
      }));
    } else if (knownSlugs.length === 0 && currentRegistered.length === 0) {
      // 7.2 UNBOUND
      status = "UNBOUND";
    } else if (missingSlugs.length > 0) {
      // 7.3 SUSPECT for removed bindings
      status = "SUSPECT";
      for (const slug of missingSlugs) {
        reasons.push({ code: "BINDING_REMOVED", binding_slug: slug });
      }
      if (currentRegistered.length === 0) {
        reasons.push({ code: "ALL_BINDINGS_REMOVED" });
      }
    } else if (currentRegistered.length > 0 && proofs.length === 0) {
      // 7.4 UNPROVEN
      status = "UNPROVEN";
    } else {
      // 7.5 FRESH if a trusted proof matches the current row + binding set. When
      // a recomputed verification context hash is supplied for the row, the proof
      // must ALSO have been minted against that same context (same verifier +
      // acceptance-test contents + lockfile); otherwise the proof is stale.
      const approval = inputRow?.approval_policy;
      const contextHashes = input.current_context_hashes;
      const currentContextHash = contextHashes?.get(rowId);
      const matches = proofs.filter((proof) => {
        if (!hashes) {
          return false;
        }
        const itemsSupported = proof.bindings.items.every(
          (item) => item.span_canon_id === SPAN_CANON_ID
        );
        const contextOk =
          contextHashes === undefined ||
          proof.verification.context_hash === currentContextHash;
        return (
          proof.row.row_hash === hashes.row_hash &&
          proof.row.verification_policy_hash === hashes.verification_policy_hash &&
          proof.row.approval_policy_hash === hashes.approval_policy_hash &&
          proof.bindings.binding_set_hash === hBind &&
          itemsSupported &&
          contextOk &&
          approvalAcceptsProof(approval, proof)
        );
      });
      if (matches.length > 0) {
        status = "FRESH";
        matching = byNewest(matches)[0];
      } else {
        // 7.6 SUSPECT for stale proof.
        status = "SUSPECT";
        reasons = deriveStaleReasons(
          latestProof,
          hashes?.row_hash ?? "",
          hashes?.verification_policy_hash ?? "",
          hashes?.approval_policy_hash ?? "",
          hBind,
          currentRegistered,
          contextHashes === undefined ? undefined : currentContextHash ?? ""
        );
      }
    }

    const required = requiredForRelease(inputRow?.approval_policy);
    // Release-gate authority requirement: only meaningful for a required, FRESH
    // row whose matching proof we have in hand. An active requirement that the
    // proof's authority does not meet flips the (otherwise unblocked) FRESH row
    // to POLICY-BLOCKED and surfaces an AUTHORITY_INSUFFICIENT reason.
    const authorityActive =
      input.policy_mode === "release" &&
      required &&
      status === "FRESH" &&
      authorityGateActive(input.release_gate);
    const authorityInsufficient =
      authorityActive && !authoritySatisfies(input.release_gate, matching?.authority);
    if (authorityInsufficient) {
      reasons.push({
        code: "AUTHORITY_INSUFFICIENT",
        message: authorityReason(input.release_gate, matching?.authority)
      });
    }
    const policyBlock = evaluatePolicyBlock(
      input.policy_mode,
      status,
      required,
      rowId,
      input.custom_policy,
      authorityInsufficient
    );

    let requiredAction: string | null = null;
    if (status === "SUSPECT" || status === "UNPROVEN") {
      requiredAction = `uc prove --row ${rowId}`;
    } else if (status === "INVALID") {
      requiredAction = "uc scan (resolve binding integrity errors)";
    } else if (status === "UNBOUND") {
      // Was null: an UNBOUND row is the single most common thing a reader needs a
      // next command for, and the core knew it but only the pre-commit formatter
      // ever said it.
      requiredAction = `uc bind --row ${rowId} --file <file> --mode <explicit|swift-func>`;
    }

    // Keyless local tier (0.1.0). Only emitted when the caller supplied
    // `local_results`. Bound rows (a registered current binding, not INVALID/
    // UNBOUND) get VERIFIED_LOCAL/STALE_LOCAL/UNVERIFIED_LOCAL; everything else
    // reports null. Never influences the signed `status` above.
    let localStatus: LocalStatus | null | undefined;
    let localReason: string | null | undefined;
    let variantLocalStatus: Array<{ key: string; local_status: LocalStatus }> | undefined;
    // A variant family: its keyless local tier is derived from ITS VARIANTS' results,
    // which verify records under `<family>::<key>` (never the family id). The family
    // is VERIFIED_LOCAL iff every declared variant is; otherwise it takes the weakest
    // variant status (STALE over UNVERIFIED). Each variant's binding-set hash mixes in
    // its own record id over the shared family span, matching what verify wrote.
    const familyVariantKeys = Array.isArray((inputRow as { variants?: unknown })?.variants)
      ? [...((inputRow as { variants?: Array<{ key: string }> }).variants ?? [])]
          .map((variant) => variant.key)
          .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0))
      : [];
    if (localResultsProvided) {
      const bound =
        status !== "INVALID" && status !== "UNBOUND" && currentRegistered.length > 0;
      if (bound && familyVariantKeys.length > 0 && status !== "FRESH") {
        const setMembers = currentRegistered.map(bindingToSetMember);
        const contextHash = input.current_context_hashes?.get(rowId);
        const breakdown = familyVariantKeys.map((key) => {
          const variantRowId = `${rowId}::${key}`;
          const derived = deriveLocalStatus(
            localResultsByRow.get(variantRowId) ?? [],
            contextHash,
            computeBindingSetHash(variantRowId, setMembers)
          );
          return { key, local_status: derived.local_status };
        });
        variantLocalStatus = breakdown;
        const allVerified = breakdown.every((entry) => entry.local_status === "VERIFIED_LOCAL");
        const anyStale = breakdown.some((entry) => entry.local_status === "STALE_LOCAL");
        localStatus = allVerified ? "VERIFIED_LOCAL" : anyStale ? "STALE_LOCAL" : "UNVERIFIED_LOCAL";
        const failing = breakdown.filter((entry) => entry.local_status !== "VERIFIED_LOCAL");
        localReason = allVerified
          ? null
          : `variant(s) not VERIFIED_LOCAL: ${failing.map((entry) => entry.key).join(", ")}`;
      } else if (bound && status === "FRESH") {
        // FRESH precedence: a trusted signed proof is a strictly stronger
        // guarantee than an unsigned local run, so it always satisfies the
        // keyless daily light — even when the throwaway verify-results ledger
        // is absent or stale locally (e.g. the proof was minted in CI and the
        // ledger, which `verify --out` overwrites, was never written here).
        // Keeps `local_status` consistent with `status` (plan: FRESH ⇒
        // VERIFIED_LOCAL) instead of showing a false non-green daily light.
        localStatus = "VERIFIED_LOCAL";
        localReason = "backed by trusted signed proof";
      } else if (bound) {
        const derived = deriveLocalStatus(
          localResultsByRow.get(rowId) ?? [],
          input.current_context_hashes?.get(rowId),
          hBind
        );
        localStatus = derived.local_status;
        localReason = derived.local_reason;
      } else {
        localStatus = null;
        localReason = null;
      }
    }

    const rowOut: FreshnessRowOut = {
      row_id: rowId,
      ...(hashes ?? {}),
      status,
      policy_block: policyBlock,
      reasons,
      known_binding_slugs: knownSlugs,
      current_binding_slugs: currentSlugs,
      missing_registered_binding_slugs: missingSlugs,
      unregistered_current_binding_slugs: unregisteredSlugs,
      current_bindings: currentRegistered.map(bindingToOut),
      matching_proof_event: matching ? proofRef(matching) : null,
      latest_trusted_proof_event: latestProof ? proofRef(latestProof) : null,
      required_action: requiredAction,
      required_for_release: required
    };
    // Emit the keyless local tier only when the caller opted in via local_results.
    if (localStatus !== undefined) {
      rowOut.local_status = localStatus;
      rowOut.local_reason = localReason ?? null;
    }
    if (variantLocalStatus !== undefined) {
      rowOut.variant_local_status = variantLocalStatus;
    }
    // Only emit a binding-set hash when the row has registered current bindings.
    if (currentRegistered.length > 0) {
      rowOut.current_binding_set_hash = hBind;
    }
    outRows.push(rowOut);
    allIntegrity.push(...rowIntegrity);

    switch (status) {
      case "FRESH":
        summary.fresh += 1;
        break;
      case "SUSPECT":
        summary.suspect += 1;
        break;
      case "UNPROVEN":
        summary.unproven += 1;
        break;
      case "UNBOUND":
        summary.unbound += 1;
        break;
      case "INVALID":
        summary.invalid += 1;
        break;
    }
    if (policyBlock) {
      summary.policy_blocked += 1;
    }

    switch (localStatus) {
      case "VERIFIED_LOCAL":
        summary.verified_local += 1;
        break;
      case "STALE_LOCAL":
        summary.stale_local += 1;
        break;
      case "UNVERIFIED_LOCAL":
        summary.unverified_local += 1;
        break;
    }

    if (status === "FRESH" || localStatus === "VERIFIED_LOCAL") {
      provenRows += 1;
    }
  }

  // guard_ok is false iff any INVALID row or any global integrity error exists.
  // NOTE: this deliberately says nothing about whether anything is PROVEN — it is
  // a policy-block check, and changing that would flip every existing CI gate.
  // `acceptance_claim` below is the field that answers the proof question.
  const guardOk = summary.invalid === 0 && globalIntegrity.length === 0;

//: @use-case:lifecycle.signals.acceptance_claim_is_honest
  const totalRows = outRows.length;
  // Acceptance is claimable only when every row is proven by some tier AND no
  // policy/integrity error is outstanding. An UNBOUND row is never proven, so a
  // matrix with unbound rows can never claim acceptance — which is the point.
  const claimable = totalRows > 0 && provenRows === totalRows && guardOk;
  const statement = claimable
    ? `SUPPORTED — ${provenRows} of ${totalRows} behaviours verified`
    : `NOT_SUPPORTED — ${provenRows} of ${totalRows} behaviours verified`;
//: @use-case:end lifecycle.signals.acceptance_claim_is_honest

  return {
    schema: STATUS_SCHEMA_ID,
    generated_at: input.generated_at,
    tool: input.tool ?? DEFAULT_TOOL,
    product_root: input.product_root ?? ".",
    policy_mode: input.policy_mode,
    guard_ok: guardOk,
    acceptance_claim: {
      proven: provenRows,
      total: totalRows,
      claimable,
      statement
    },
    summary,
    integrity_errors: allIntegrity,
    rows: outRows
  };
}
