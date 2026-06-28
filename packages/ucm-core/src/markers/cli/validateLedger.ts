// `validate-ledger` command core (spec 8.4; Phase 7).
//
// Validates append-only discipline, schemas, signatures, producer trust, pass
// result, internal binding_set_hash recompute, and registry slug->row mapping +
// uniqueness. It is the AUTHORITY on ledger/registry integrity. It MUST NOT
// compare old proof spans to current code, MUST NOT mutate, and MUST NOT derive
// freshness (those are scan's job). Exit codes follow spec 8.4 (0/2/4).
import type { ResolvedWorkspaceContext } from "../../roots.js";
import {
  appendOnly,
  readBaseRefFile,
  splitJsonlLines,
  type GitRunner
} from "../appendOnly.js";
import { validateEvidenceLedger } from "../evidenceLedger.js";
import { validateBindingsJsonl } from "../registry.js";
import type { PublicKeyResolver } from "../proofSignature.js";
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import { loadMarkerRows } from "./shared.js";

export interface ValidateLedgerCommandOptions {
  context: ResolvedWorkspaceContext;
  evidencePath: string;
  bindingsPath: string;
  publicKeyResolver: PublicKeyResolver;
  baseRef?: string;
  gitRunner?: GitRunner;
  repoCwd?: string;
  fs?: MarkerFs;
}

export interface LedgerErrorOut {
  scope: "evidence" | "registry";
  code: string;
  line: number | null;
  message: string;
}

export interface ValidateLedgerCommandResult {
  exit_code: number;
  ok: boolean;
  command: "validate-ledger";
  evidence_valid: boolean;
  registry_valid: boolean;
  append_only: boolean;
  proof_events_checked: number;
  registry_events_checked: number;
  errors: LedgerErrorOut[];
}

export function runValidateLedgerCommand(
  options: ValidateLedgerCommandOptions
): ValidateLedgerCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const loaded = loadMarkerRows(options.context);
  const errors: LedgerErrorOut[] = [];

  // --- Evidence ledger (spec 8.4 steps 1,3,4,6-9) ---
  const evidenceText = fs.readText(options.evidencePath) ?? "";
  const evidenceBaseText =
    options.baseRef !== undefined
      ? readBaseRefFile(options.baseRef, options.evidencePath, {
          cwd: options.repoCwd,
          runner: options.gitRunner
        })
      : undefined;
  const evidenceResult = validateEvidenceLedger(evidenceText, {
    publicKeyResolver: options.publicKeyResolver,
    yamlRowIds: loaded.rowIds,
    baseRefOldText: evidenceBaseText
  });
  for (const error of evidenceResult.errors) {
    errors.push({ scope: "evidence", code: error.code, line: error.line, message: error.message });
  }

  // --- Binding registry (spec 8.4 steps 2,3,5,10-12) ---
  const bindingsText = fs.readText(options.bindingsPath) ?? "";
  const registryResult = validateBindingsJsonl(bindingsText, loaded.rowIds);
  for (const error of registryResult.errors) {
    errors.push({ scope: "registry", code: error.code, line: error.line, message: error.message });
  }

  // Registry append-only vs base ref (spec 8.4 step 5).
  let registryAppendOnly = true;
  if (options.baseRef !== undefined) {
    const oldText = readBaseRefFile(options.baseRef, options.bindingsPath, {
      cwd: options.repoCwd,
      runner: options.gitRunner
    });
    const check = appendOnly(splitJsonlLines(oldText), splitJsonlLines(bindingsText));
    if (!check.ok) {
      registryAppendOnly = false;
      errors.push({
        scope: "registry",
        code: "APPEND_ONLY_VIOLATION",
        line: check.violation.index + 1,
        message: check.violation.message
      });
    }
  }

  const evidenceValid = evidenceResult.errors.length === 0;
  const registryValid = registryResult.errors.length === 0 && registryAppendOnly;
  const appendOnlyOk = evidenceResult.append_only && registryAppendOnly;
  const ok = evidenceValid && registryValid;

  return {
    exit_code: ok ? 0 : 4,
    ok,
    command: "validate-ledger",
    evidence_valid: evidenceValid,
    registry_valid: registryValid,
    append_only: appendOnlyOk,
    proof_events_checked: evidenceResult.summary.proof_events_checked,
    registry_events_checked: countJsonlLines(bindingsText),
    errors
  };
}

function countJsonlLines(text: string): number {
  return splitJsonlLines(text).filter((line) => line.trim() !== "").length;
}
