// `scan` command core (spec 8.2; Phase 7).
//
// Loads rows, validates the append-only registry + evidence ledger, scans product
// source for markers, derives freshness, and emits the spec-section-6 status
// object. It is strictly read-only: it never writes source, registry, or evidence
// (acceptance criterion 4). Exit codes follow spec 8.2 (0/1/3/4).
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import {
  validateEvidenceLedger,
  isKeyResolutionOnlyError,
  type ProofEvent,
  type EvidenceError
} from "../evidenceLedger.js";
import {
  deriveFreshness,
  type FreshnessStatus,
  type LocalVerificationResult,
  type PolicyMode
} from "../freshness.js";
import type { PublicKeyResolver } from "../proofSignature.js";
import {
  validateBindingsJsonl,
  type MaterializedRegistry,
  type RegistryError
} from "../registry.js";
import {
  formatInferredSwiftSpanReport,
  scanFiles,
  type ScanResult
} from "../scanner.js";
import { readBaseRefFile, type GitRunner } from "../appendOnly.js";
import { computeRowVerificationContextHash } from "../verificationContextHash.js";
import { join } from "node:path";
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import {
  collectSourceInputs,
  loadMarkerRows,
  type LoadedMarkerRows
} from "./shared.js";

// The conventional location of the UNSIGNED verification-results ledger, one row
// per line, that `verify --out` writes. Scan auto-discovers it here (under the
// data root's .use-cases dir) so the keyless daily loop — bind -> verify -> scan
// -> VERIFIED_LOCAL — needs no key, no CI, and no extra flags.
export const DEFAULT_VERIFICATION_RESULTS_FILENAME = "verification-results.jsonl";

// Parse the unsigned verification-results ledger (JSONL of
// `ucase-verification-result-v1` records) into the minimal shape freshness's
// keyless tier consumes. Unreadable/blank/malformed content yields an empty list
// (the keyless signal is best-effort and NEVER blocks the read-only scan).
function loadLocalVerificationResults(text: string): LocalVerificationResult[] {
  const results: LocalVerificationResult[] = [];
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line === "") {
      continue;
    }
    let record: unknown;
    try {
      record = JSON.parse(line);
    } catch {
      continue; // skip a malformed line rather than failing the whole scan
    }
    if (typeof record !== "object" || record === null) {
      continue;
    }
    const value = record as Record<string, unknown>;
    const rowId = value.row_id;
    const contextHash = value.verification_context_hash;
    const bindingSetHash = value.binding_set_hash;
    const status = value.status;
    if (
      typeof rowId !== "string" ||
      typeof contextHash !== "string" ||
      typeof bindingSetHash !== "string" ||
      typeof status !== "string"
    ) {
      continue;
    }
    results.push({
      row_id: rowId,
      context_hash: contextHash,
      binding_set_hash: bindingSetHash,
      passed: status === "pass"
    });
  }
  return results;
}

export interface ScanCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  policyMode: PolicyMode;
  publicKeyResolver: PublicKeyResolver;
  // Whether the caller actually configured trusted key material (a --public-key
  // or --keyring). Defaults to true (conservative: any unresolved key_id is a
  // trust failure — e.g. a revoked/expired keyring key — and fails closed). When
  // FALSE (the keyless daily path — no key flag at all), a signed proof that
  // cannot be checked is NOT corruption: it is the ordinary keyless case, the row
  // reads UNPROVEN, and scan stays exit 0 so the green human view is truthful.
  trustedKeyConfigured?: boolean;
  generatedAt: string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  // When set, the registry/evidence ledgers are also checked append-only vs ref.
  baseRef?: string;
  gitRunner?: GitRunner;
  // When set, registry/evidence are read relative to this dir for the base ref.
  repoCwd?: string;
  // OPTIONAL override for the UNSIGNED verification-results ledger (`verify --out`)
  // that feeds the keyless VERIFIED_LOCAL tier. Defaults to
  // <data_root>/.use-cases/verification-results.jsonl. Absent file => no local tier.
  resultsPath?: string;
  // OPT-IN exit-code gate (0.1.0). When true, a REQUIRED row below the mode's
  // acceptable bar makes scan exit 1 (see evaluateScanGate). Off by default so
  // scan's exit code is backward-compatible (0 even for SUSPECT).
  gate?: boolean;
}

export interface ScanPreparation {
  loaded: LoadedMarkerRows;
  registry: MaterializedRegistry;
  registryErrors: RegistryError[];
  evidence: ProofEvent[];
  evidenceErrors: EvidenceError[];
  // The subset of evidenceErrors that are REAL ledger corruption (everything
  // except pure missing-key failures). This is what should flip evidence_valid /
  // drive an exit-4 integrity failure — a signed proof the caller simply has no
  // key to check is the ordinary keyless path, not corruption.
  evidenceIntegrityErrors: EvidenceError[];
  scan: ScanResult;
  status: FreshnessStatus;
}

// Shared pipeline used by both `scan` and `prove` (prove runs scan first).
export function prepareScan(options: ScanCommandOptions): ScanPreparation {
  const fs = options.fs ?? nodeMarkerFs;
  const loaded = loadMarkerRows(options.context);

  // Registry (append-only binding log) -> validate + materialize. Append-only
  // discipline vs a base ref is validate-ledger's authority (spec 8.4); scan only
  // validates the materialized registry here.
  const bindingsText = fs.readText(options.bindingsPath) ?? "";
  const registryResult = validateBindingsJsonl(bindingsText, loaded.rowIds);
  const registryErrors = [...registryResult.errors];

  // Evidence ledger -> validate signatures/schema/policy/internal hashes.
  const evidenceText = fs.readText(options.evidencePath) ?? "";
  const baseRefOldText =
    options.baseRef !== undefined
      ? readBaseRefFile(options.baseRef, options.evidencePath, {
          cwd: options.repoCwd,
          runner: options.gitRunner
        })
      : undefined;
  const evidenceResult = validateEvidenceLedger(evidenceText, {
    publicKeyResolver: options.publicKeyResolver,
    yamlRowIds: loaded.rowIds,
    baseRefOldText
  });

  // Scan product source for markers.
  const inputs = collectSourceInputs(options.productRoot, {
    fs,
    config: options.commentConfig,
    skipPaths: [options.context.data_root]
  });
  const scan = scanFiles(inputs, { config: options.commentConfig });

  // A pure missing-key failure (a signed proof present, no key supplied to check
  // it) is NOT ledger corruption — it is the ordinary keyless path. Such a proof
  // is already dropped from the trusted `events` set (its signature did not
  // verify), so its row correctly reads UNPROVEN; the keyless VERIFIED_LOCAL tier
  // still applies. So it must NOT flip evidence_valid, NOT become a global
  // integrity error, and NOT force an exit-4 "ledger invalid". Only REAL
  // corruption (BAD_SIGNATURE, malformed/append-violating/schema-invalid) does.
  //
  // This grace applies ONLY when NO trusted key was configured (the keyless
  // path). When a key/keyring IS configured, an unresolved key_id is a real trust
  // decision (revoked / expired / wrong id) and MUST fail closed — so key-only
  // errors stay integrity errors there.
  const keyConfigured = options.trustedKeyConfigured ?? true;
  const evidenceIntegrityErrors = keyConfigured
    ? evidenceResult.errors
    : evidenceResult.errors.filter((error) => !isKeyResolutionOnlyError(error));

  // Derive freshness. Registry/ledger corruption become global integrity errors
  // so guard_ok flips and they surface in the status object. Key-only failures
  // are excluded (see above).
  const globalIntegrity = [
    ...registryErrors.map((error) => ({
      code: error.code,
      line: error.line ?? undefined,
      message: error.message,
      binding_slug: error.binding_slug
    })),
    ...evidenceIntegrityErrors.map((error) => ({
      code: error.code,
      line: error.line ?? undefined,
      message: error.message,
      event_id: error.event_id
    }))
  ];

  // Freshly recompute each row's verification context hash from the CURRENT
  // resolved verifier + declared-input contents + lockfile. Threaded into
  // freshness so a proof minted against a now-weakened verifier is no longer
  // FRESH. Computed identically to `prove` (same root + fs), so a just-minted
  // proof's embedded hash matches its recomputed value.
  const contextRoot = options.repoCwd ?? options.productRoot;
  const currentContextHashes = new Map<string, string>();
  for (const row of loaded.rows) {
    currentContextHashes.set(
      row.row_id,
      computeRowVerificationContextHash({
        slug: row.row_id,
        verificationPolicy: row.verification_policy,
        rootDir: contextRoot,
        fs,
        workspaceVerifiers: options.context.verifiers
      })
    );
  }

  // Keyless local tier: auto-discover the UNSIGNED verification-results ledger
  // (what `verify --out` writes) under the data root, or use the caller override.
  // Read-only and best-effort: an absent/unreadable file simply yields no local
  // results, and the local tier is reported as UNVERIFIED_LOCAL for bound rows.
  const resultsPath =
    options.resultsPath ??
    join(options.context.data_root, ".use-cases", DEFAULT_VERIFICATION_RESULTS_FILENAME);
  const resultsText = fs.readText(resultsPath);
  const localResults =
    resultsText == null ? [] : loadLocalVerificationResults(resultsText);

  const status = deriveFreshness({
    rows: loaded.rows,
    registry: registryResult.registry,
    scan,
    evidence: evidenceResult.events,
    policy_mode: options.policyMode,
    generated_at: options.generatedAt,
    product_root: options.productRoot,
    current_context_hashes: currentContextHashes,
    local_results: localResults,
    global_integrity_errors: globalIntegrity,
    // OPTIONAL CI-neutral release-gate authority requirement from workspace
    // config (off by default). Only consulted in release mode by deriveFreshness.
    release_gate: options.context.release_gate
  });

  return {
    loaded,
    registry: registryResult.registry,
    registryErrors,
    evidence: evidenceResult.events,
    evidenceErrors: evidenceResult.errors,
    evidenceIntegrityErrors,
    scan,
    status
  };
}

export interface ScanCommandResult {
  exit_code: number;
  ok: boolean;
  status: FreshnessStatus;
  registry_valid: boolean;
  evidence_valid: boolean;
  inferred_spans: string[];
  registry_errors: RegistryError[];
  evidence_errors: EvidenceError[];
  // Present ONLY when --gate was requested (a `gate.blocked` diagnostic listing
  // offending required rows). Absent otherwise, so the default envelope is
  // byte-identical to pre-0.1.0.
  gate?: ScanGateResult;
}

export function runScanCommand(options: ScanCommandOptions): ScanCommandResult {
  const prepared = prepareScan(options);
  const registryValid = prepared.registryErrors.length === 0;
  // evidence_valid / the exit code turn ONLY on real corruption. A pure
  // missing-key failure (signed proof present, no key to check it) is the
  // ordinary keyless path, not a ledger-integrity failure — the row already
  // reads UNPROVEN, and the keyless VERIFIED_LOCAL tier keeps the green light
  // truthful. This keeps exit 0 (== the human green view) consistent.
  const evidenceValid = prepared.evidenceIntegrityErrors.length === 0;

  // Inferred Swift spans, for the CI human report (spec 8.2 "must print").
  const inferredSpans = prepared.scan.bindings
    .map((binding) => formatInferredSwiftSpanReport(binding))
    .filter((report): report is string => report !== null);

  const baseExitCode = scanExitCode(prepared.status, registryValid, evidenceValid);

  // Opt-in gate: escalate an otherwise-passing scan (exit 0) to exit 1 when a
  // required row is below the bar. It NEVER lowers a higher-precedence failure
  // (4 ledger/registry, 3 binding integrity) — those already surface real
  // problems and outrank a freshness gate. Without --gate, nothing changes.
  let gate: ScanGateResult | undefined;
  let exitCode = baseExitCode;
  if (options.gate) {
    gate = evaluateScanGate(prepared.status, options.policyMode);
    if (gate.blocked && exitCode === 0) {
      exitCode = 1;
    }
  }

  return {
    exit_code: exitCode,
    ok: exitCode === 0,
    status: prepared.status,
    registry_valid: registryValid,
    evidence_valid: evidenceValid,
    inferred_spans: inferredSpans,
    registry_errors: prepared.registryErrors,
    evidence_errors: prepared.evidenceErrors,
    ...(gate !== undefined ? { gate } : {})
  };
}

// --- scan --gate (0.1.0) ------------------------------------------------------
//
// `scan --gate` is an OPT-IN exit-code gate. WITHOUT it, scan's exit code is
// unchanged (0 even for SUSPECT). WITH it, scan exits 1 when any REQUIRED row is
// below the mode's acceptable bar:
//   - policy_mode "release" => the bar is FRESH (a trusted signed proof).
//   - otherwise (feature/custom/dev) => the bar is "at least VERIFIED_LOCAL",
//     i.e. the keyless local green light (VERIFIED_LOCAL) OR the stronger FRESH.
// Only rows marked `required_for_release` are gated; everything else is advisory.
export interface ScanGateOffender {
  row_id: string;
  status: FreshnessStatus["rows"][number]["status"];
  local_status: FreshnessStatus["rows"][number]["local_status"];
}

export interface ScanGateResult {
  blocked: boolean;
  policy_mode: PolicyMode;
  // The acceptable bar for this mode, for the diagnostic ("FRESH" or the keyless
  // "VERIFIED_LOCAL" floor).
  required_bar: "FRESH" | "VERIFIED_LOCAL";
  offending_rows: ScanGateOffender[];
}

// True iff a row meets the acceptable bar for `policyMode`. FRESH always passes
// (it strictly outranks the keyless local tier).
function rowMeetsGateBar(
  row: FreshnessStatus["rows"][number],
  policyMode: PolicyMode
): boolean {
  if (row.status === "FRESH") {
    return true;
  }
  if (policyMode === "release") {
    return false; // release bar is FRESH; nothing else clears it.
  }
  return row.local_status === "VERIFIED_LOCAL";
}

// Pure gate decision over an already-derived FreshnessStatus. Never mutates the
// status and never changes the signed `status` — it only reads it.
export function evaluateScanGate(
  status: FreshnessStatus,
  policyMode: PolicyMode
): ScanGateResult {
  const offending: ScanGateOffender[] = [];
  for (const row of status.rows) {
    if (row.required_for_release !== true) {
      continue; // only required rows are gated
    }
    if (!rowMeetsGateBar(row, policyMode)) {
      offending.push({
        row_id: row.row_id,
        status: row.status,
        local_status: row.local_status ?? null
      });
    }
  }
  return {
    blocked: offending.length > 0,
    policy_mode: policyMode,
    required_bar: policyMode === "release" ? "FRESH" : "VERIFIED_LOCAL",
    offending_rows: offending
  };
}

// Exit-code precedence (spec 8.2): 4 ledger/registry > 3 binding integrity (any
// INVALID row) > 1 freshness policy block (a non-INVALID row the policy blocks).
export function scanExitCode(
  status: FreshnessStatus,
  registryValid: boolean,
  evidenceValid: boolean
): number {
  if (!registryValid || !evidenceValid) {
    return 4;
  }
  if (status.summary.invalid > 0) {
    return 3;
  }
  const policyBlockNonInvalid = status.rows.some(
    (row) => row.policy_block && row.status !== "INVALID"
  );
  if (policyBlockNonInvalid) {
    return 1;
  }
  return 0;
}
