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
}

export interface ScanPreparation {
  loaded: LoadedMarkerRows;
  registry: MaterializedRegistry;
  registryErrors: RegistryError[];
  evidence: ProofEvent[];
  evidenceErrors: EvidenceError[];
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

  // Derive freshness. Registry/ledger validation failures become global
  // integrity errors so guard_ok flips and they surface in the status object.
  const globalIntegrity = [
    ...registryErrors.map((error) => ({
      code: error.code,
      line: error.line ?? undefined,
      message: error.message,
      binding_slug: error.binding_slug
    })),
    ...evidenceResult.errors.map((error) => ({
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
}

export function runScanCommand(options: ScanCommandOptions): ScanCommandResult {
  const prepared = prepareScan(options);
  const registryValid = prepared.registryErrors.length === 0;
  const evidenceValid = prepared.evidenceErrors.length === 0;

  // Inferred Swift spans, for the CI human report (spec 8.2 "must print").
  const inferredSpans = prepared.scan.bindings
    .map((binding) => formatInferredSwiftSpanReport(binding))
    .filter((report): report is string => report !== null);

  const exitCode = scanExitCode(prepared.status, registryValid, evidenceValid);
  return {
    exit_code: exitCode,
    ok: exitCode === 0,
    status: prepared.status,
    registry_valid: registryValid,
    evidence_valid: evidenceValid,
    inferred_spans: inferredSpans,
    registry_errors: prepared.registryErrors,
    evidence_errors: prepared.evidenceErrors
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
