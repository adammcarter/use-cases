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
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import {
  collectSourceInputs,
  loadMarkerRows,
  type LoadedMarkerRows
} from "./shared.js";

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

  const status = deriveFreshness({
    rows: loaded.rows,
    registry: registryResult.registry,
    scan,
    evidence: evidenceResult.events,
    policy_mode: options.policyMode,
    generated_at: options.generatedAt,
    product_root: options.productRoot,
    current_context_hashes: currentContextHashes,
    global_integrity_errors: globalIntegrity
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
