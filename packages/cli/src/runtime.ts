// Shared runtime for the declarative command registry. It loads core through the
// same fallback path the legacy dispatcher uses, and provides NON-WRITING ports
// of the legacy `contextFromArgs` / `writeError` helpers: registry handlers must
// return an envelope rather than write stdout, so these return the envelope (and
// exit code) instead of emitting it. The envelopes are constructed identically to
// the legacy ones, so `--json` output stays byte-for-byte the same.
import { isAbsolute, relative, resolve } from "node:path";
import { loadUcmCore } from "./coreLoader.js";
import { valueAfter } from "./args/parse.js";

const core = await loadUcmCore();

export const {
  PUBLIC_SCHEMA_IDS,
  createCliResult,
  validateFixtureWorkspace,
  resolveWorkspaceContext,
  workspaceNotFoundDiagnostic,
  loadUseCaseMatrix,
  queryUseCases,
  toMatrixValidationResult,
  toMatrixListResult,
  replayEvidence,
  toEvidenceStatusResult,
  toEvidenceAppendResult,
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  loadDemoCapsules,
  planDemoCapsule,
  runDemoCapsule,
  mutateUseCaseMatrix,
  selectShowcasePlan,
  selectWalkthroughPlan,
  loadPresentationPlanFile,
  renderCard,
  resolveContainedPath,
  isValidId,
  migrateTestMatrix,
  loadHostProfile,
  projectHostFiles,
  runHostConformance,
  runHostDoctor,
  validateSkillAssets,
  inspectPackageArtifact,
  runBindCommand,
  runScanCommand,
  runProveCommand,
  runVerifyCommand,
  runValidateLedgerCommand,
  runImpactCommand,
  DEFAULT_VERIFICATION_RESULTS_FILENAME,
  detectCiAuthority,
  singleKeyResolver,
  keyringPublicKeyResolverFromFile,
  keyringResolver,
  keyringAssuranceTierResolver,
  loadKeyring,
  parseKeyring,
  AssuranceTier,
  generateSigningKeypair,
  replayShowcaseRun,
  startShowcaseRun,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  appendShowcaseFailureDecision,
  appendShowcaseApproval,
  rejectShowcaseApproval,
  correctShowcaseVerdict,
  computeRunApprovalBinding,
  finishShowcaseRun,
  pauseShowcaseRun,
  resumeShowcaseRun,
  mintApprovalRequest,
  signApprovalToken
} = core;

// Hosts the CLI supports (mirrors the legacy SUPPORTED_HOSTS constant).
export const SUPPORTED_HOSTS = ["claude", "codex", "copilot", "opencode"] as const;

export type CliEnvelope = ReturnType<typeof createCliResult>;
export type ResolvedContext = ReturnType<typeof resolveWorkspaceContext>;

// Build an error envelope identical to the one the legacy `writeError` emits, but
// return it instead of writing — the dispatcher renders it.
export function errorEnvelope(command: string, code: string, message: string): CliEnvelope {
  return createCliResult(
    command,
    {},
    {
      ok: false,
      complete: false,
      diagnostics: [
        {
          code,
          severity: "error",
          message,
          source_path: null,
          json_pointer: null,
          entity_id: null,
          related_ids: []
        }
      ]
    }
  );
}

// Render any thrown value as the standard error envelope. A UseCasesPluginError
// carries a stable `.code`; anything else collapses to `internal_error`. This
// mirrors the MCP server's top-level tool catch, so a thrown failure degrades to
// the same ok:false envelope over the CLI as it does over MCP — never a bare
// Node stack trace on stderr with empty stdout.
export function caughtErrorEnvelope(command: string, error: unknown): CliEnvelope {
  const code = error instanceof Error && "code" in error ? String((error as { code?: unknown }).code) : "internal_error";
  const message = error instanceof Error ? error.message : String(error);
  return errorEnvelope(command, code, message);
}

// Non-writing port of the legacy `containedFilePath`: bound a user-supplied path
// to the workspace, returning a tagged error (envelope + exit 4) on escape.
export type ContainedPathResult =
  | { readonly kind: "ok"; readonly path: string }
  | { readonly kind: "error"; readonly envelope: CliEnvelope; readonly exitCode: number };

export function containedPathOrError(command: string, workspaceRoot: string, candidate: string): ContainedPathResult {
  try {
    return { kind: "ok", path: resolveContainedPath(workspaceRoot, candidate) };
  } catch (error) {
    if (error instanceof Error && "code" in error && (error as { code?: unknown }).code === "path.escape") {
      return { kind: "error", envelope: errorEnvelope(command, "UCM_PATH_ESCAPE", error.message), exitCode: 4 };
    }
    throw error;
  }
}

export type ContextResult =
  | { readonly kind: "ok"; readonly context: ResolvedContext }
  | { readonly kind: "error"; readonly envelope: CliEnvelope; readonly exitCode: number };

// Non-writing port of the legacy `contextFromArgs`: resolve workspace context
// from --repo/--data-root/--component, returning a tagged error (envelope + exit
// 4) when --data-root escapes --repo, exactly as the legacy guard did.
export function resolveContextOrError(argv: string[], command: string): ContextResult {
  const workspaceRoot = resolve(process.cwd(), valueAfter(argv, "--repo") ?? ".");
  // Shared workspace-existence guard (core): a non-existent --repo is a typo, not a
  // valid empty workspace. Exit 2 = usage/lookup failure (distinct from 4 = unsafe
  // path). The MCP transport applies the SAME core guard, so both emit an identical
  // workspace.not_found envelope. (An existing-but-empty directory is still
  // legitimate — that stays the "not populated" case.)
  const missing = workspaceNotFoundDiagnostic(workspaceRoot);
  if (missing) {
    return { kind: "error", envelope: errorEnvelope(command, missing.code, missing.message), exitCode: 2 };
  }
  const dataRootValue = valueAfter(argv, "--data-root");
  if (dataRootValue) {
    const dataRoot = resolve(process.cwd(), dataRootValue);
    const rel = relative(workspaceRoot, dataRoot);
    if (rel === ".." || rel.startsWith(`..${"/"}`) || isAbsolute(rel)) {
      return {
        kind: "error",
        envelope: errorEnvelope(command, "unsafe_data_root", "--data-root must stay inside --repo."),
        exitCode: 4
      };
    }
  }
  return {
    kind: "ok",
    context: resolveWorkspaceContext({
      workspaceRoot,
      dataRootOverride: dataRootValue ? resolve(process.cwd(), dataRootValue) : undefined,
      component: valueAfter(argv, "--component")
    })
  };
}
