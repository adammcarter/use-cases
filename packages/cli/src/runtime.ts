// Shared runtime for the declarative command registry. It loads core through the
// same fallback path the legacy dispatcher uses, and provides NON-WRITING ports
// of the legacy `contextFromArgs` / `writeError` helpers: registry handlers must
// return an envelope rather than write stdout, so these return the envelope (and
// exit code) instead of emitting it. The envelopes are constructed identically to
// the legacy ones, so `--json` output stays byte-for-byte the same.
import { isAbsolute, relative, resolve } from "node:path";
import { loadUcmCore } from "./legacy.js";
import { valueAfter } from "./args/parse.js";

const core = await loadUcmCore();

export const {
  PUBLIC_SCHEMA_IDS,
  createCliResult,
  validateFixtureWorkspace,
  resolveWorkspaceContext,
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
  detectCiAuthority,
  singleKeyResolver,
  keyringPublicKeyResolverFromFile,
  replayShowcaseRun,
  startShowcaseRun,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  appendShowcaseFailureDecision,
  appendShowcaseApproval,
  rejectShowcaseApproval,
  correctShowcaseVerdict,
  finishShowcaseRun,
  pauseShowcaseRun,
  resumeShowcaseRun
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
      return { kind: "error", envelope: errorEnvelope(command, "UCP_PATH_ESCAPE", error.message), exitCode: 4 };
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
