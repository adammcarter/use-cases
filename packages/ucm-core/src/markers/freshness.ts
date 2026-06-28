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
import { PROOF_PASS_RESULT, type ProofEvent } from "./evidenceLedger.js";
import type { MaterializedRegistry } from "./registry.js";
import type { CurrentBindingRecord, MarkerError, ScanResult } from "./scanner.js";

export type RowStatus = "FRESH" | "SUSPECT" | "UNPROVEN" | "UNBOUND" | "INVALID";
export type PolicyMode = "feature" | "release" | "custom";

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
}

export interface FreshnessSummary {
  fresh: number;
  suspect: number;
  unproven: number;
  unbound: number;
  invalid: number;
  policy_blocked: number;
}

export interface FreshnessStatus {
  schema: typeof STATUS_SCHEMA_ID;
  generated_at: string;
  tool: { name: string; version: string };
  product_root: string;
  policy_mode: PolicyMode;
  guard_ok: boolean;
  summary: FreshnessSummary;
  integrity_errors: IntegrityErrorOut[];
  rows: FreshnessRowOut[];
}

const DEFAULT_TOOL = { name: "use-cases-plugin", version: "0.1.0" };

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
  current: CurrentBindingRecord[]
): FreshnessReason[] {
  const reasons: FreshnessReason[] = [];
  if (!latest) {
    reasons.push({ code: "NO_MATCHING_TRUSTED_PROOF" });
    return reasons;
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

function evaluatePolicyBlock(
  mode: PolicyMode,
  status: RowStatus,
  required: boolean,
  rowId: string,
  custom?: CustomPolicyPredicate
): boolean {
  const isInvalid = status === "INVALID";
  if (mode === "feature") {
    return isInvalid; // feature blocks only INVALID (spec 10.2 / 8.2)
  }
  if (mode === "release") {
    // release blocks INVALID and any required row that is not FRESH (spec 10.2).
    return isInvalid || (required && status !== "FRESH");
  }
  // custom: defer to the configured predicate; default to feature behaviour.
  if (custom) {
    return custom({ row_id: rowId, status, required_for_release: required, is_invalid: isInvalid });
  }
  return isInvalid;
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
    policy_blocked: 0
  };

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
      rowIntegrity.push({
        code: "UNREGISTERED_BINDING",
        row_id: rowId,
        binding_slug: detection.binding_slug,
        file_path: detection.file_path,
        line: detection.start_line,
        message: `current marker ${detection.binding_slug} is not registered in the binding registry`
      });
    }
    if (!inputRow) {
      // A marker/registry references a row that does not exist in the loaded
      // rows (spec 7.1 "marker row id does not exist" / "registry row id does
      // not exist").
      rowIntegrity.push({
        code: "ROW_NOT_FOUND",
        row_id: rowId,
        message: `row ${rowId} is bound or registered but is not a known use-case row`
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
      // 7.5 FRESH if a trusted proof matches the current row + binding set.
      const approval = inputRow?.approval_policy;
      const matches = proofs.filter((proof) => {
        if (!hashes) {
          return false;
        }
        const itemsSupported = proof.bindings.items.every(
          (item) => item.span_canon_id === SPAN_CANON_ID
        );
        return (
          proof.row.row_hash === hashes.row_hash &&
          proof.row.verification_policy_hash === hashes.verification_policy_hash &&
          proof.row.approval_policy_hash === hashes.approval_policy_hash &&
          proof.bindings.binding_set_hash === hBind &&
          itemsSupported &&
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
          currentRegistered
        );
      }
    }

    const required = requiredForRelease(inputRow?.approval_policy);
    const policyBlock = evaluatePolicyBlock(
      input.policy_mode,
      status,
      required,
      rowId,
      input.custom_policy
    );

    let requiredAction: string | null = null;
    if (status === "SUSPECT" || status === "UNPROVEN") {
      requiredAction = `use-cases prove --row ${rowId}`;
    } else if (status === "INVALID") {
      requiredAction = "use-cases scan (resolve binding integrity errors)";
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
      required_action: requiredAction
    };
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
  }

  // guard_ok is false iff any INVALID row or any global integrity error exists.
  const guardOk = summary.invalid === 0 && globalIntegrity.length === 0;

  return {
    schema: STATUS_SCHEMA_ID,
    generated_at: input.generated_at,
    tool: input.tool ?? DEFAULT_TOOL,
    product_root: input.product_root ?? ".",
    policy_mode: input.policy_mode,
    guard_ok: guardOk,
    summary,
    integrity_errors: allIntegrity,
    rows: outRows
  };
}
