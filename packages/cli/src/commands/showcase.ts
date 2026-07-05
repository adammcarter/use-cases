import { readFileSync } from "node:fs";
import { createPublicKey } from "node:crypto";
import { resolve } from "node:path";
import type { CliCommand, CommandOutput, ParsedFlags } from "../command/types.js";
import {
  appendShowcaseApproval,
  appendShowcaseFailureDecision,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  AssuranceTier,
  computeRunApprovalBinding,
  containedPathOrError,
  correctShowcaseVerdict,
  createCliResult,
  errorEnvelope,
  finishShowcaseRun,
  isValidId,
  keyringAssuranceTierResolver,
  keyringWebAuthnCredentialResolver,
  keyringResolver,
  loadKeyring,
  loadPresentationPlanFile,
  loadUseCaseMatrix,
  mintApprovalRequest,
  parseKeyring,
  pauseShowcaseRun,
  rejectShowcaseApproval,
  replayEvidence,
  replayShowcaseRun,
  resolveContextOrError,
  resumeShowcaseRun,
  selectShowcasePlan,
  singleKeyResolver,
  startShowcaseRun,
  type ResolvedContext
} from "../runtime.js";
import { workspaceFlags } from "./common.js";

// F3 trusted approval submit path (BLOCKER 1): build the (approvalToken,
// publicKeyResolver, tierResolver) bundle a trusted human sign-off requires.
// A workspace-pinned approval_trust anchor wins; flags can only narrow it.
// Returns null when no --approval-token was supplied (the additive,
// backward-compatible default: untrusted_automation, user-required plans stay
// pending). Throws a coded error (rendered as ok:false, exit 1) when the
// token/key material is unreadable.
interface TrustResolvers {
  resolver: ReturnType<typeof singleKeyResolver>;
  tierResolver: ReturnType<typeof keyringAssuranceTierResolver>;
  webauthnCredentialResolver: ReturnType<typeof keyringWebAuthnCredentialResolver>;
  diagnostics: CliDiagnostic[];
  pinnedKeyIds?: Set<string>;
}

interface ApprovalTokenBundle extends TrustResolvers {
  approvalToken: unknown;
}

type Keyring = ReturnType<typeof loadKeyring>;
type KeyringKey = Keyring["keys"][number];
type CliDiagnostic = ReturnType<typeof createCliResult>["diagnostics"][number];

function keyMaterialError(message: string, code: string): Error {
  const error = new Error(message);
  (error as { code?: string }).code = code;
  return error;
}

function callerSuppliedTrustDiagnostic(): CliDiagnostic {
  return {
    code: "showcase.approval_trust_anchor_caller_supplied",
    severity: "warning",
    message: "Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.",
    source_path: null,
    json_pointer: null,
    entity_id: null,
    related_ids: []
  };
}

function keyringFromKeys(keys: KeyringKey[], sourcePath: string | null = null): Keyring {
  return parseKeyring(
    {
      keyring_schema_id: "ucase-public-key-registry-v1",
      keys
    },
    sourcePath
  );
}

function keyIds(keyring: Keyring): Set<string> {
  return new Set(
    keyring.keys.map((key) => key.algorithm === "webauthn" ? key.credential_id : key.key_id)
  );
}

function resolversForKeyring(keyring: Keyring, diagnostics: CliDiagnostic[] = [], pinnedKeyIds?: Set<string>): TrustResolvers {
  return {
    resolver: keyringResolver(keyring),
    tierResolver: keyringAssuranceTierResolver(keyring),
    webauthnCredentialResolver: keyringWebAuthnCredentialResolver(keyring),
    diagnostics,
    ...(pinnedKeyIds ? { pinnedKeyIds } : {})
  };
}

function emptyTrustResolvers(pinnedKeyIds: Set<string>): TrustResolvers {
  return {
    resolver: () => undefined,
    tierResolver: () => undefined,
    webauthnCredentialResolver: () => undefined,
    diagnostics: [],
    pinnedKeyIds
  };
}

function loadPinnedApprovalTrustKeyring(context: ResolvedContext): Keyring | null {
  const pinned = context.approval_trust;
  if (!pinned) {
    return null;
  }
  const keys: KeyringKey[] = [];
  if (pinned.keyring_path) {
    try {
      keys.push(...loadKeyring(resolve(context.workspace_root, pinned.keyring_path)).keys);
    } catch (error) {
      throw keyMaterialError(
        `could not read approval_trust.keyring_path: ${error instanceof Error ? error.message : String(error)}`,
        "showcase.approval_trust_keyring_unreadable"
      );
    }
  }
  if (pinned.keyring) {
    keys.push(...pinned.keyring.keys);
  }
  if (pinned.public_keys) {
    keys.push(...pinned.public_keys);
  }
  if (keys.length === 0) {
    return null;
  }
  return keyringFromKeys(keys, "use-cases.yml#/approval_trust");
}

function readPublicKeyFlag(publicKeyPath: string): { publicKey: ReturnType<typeof createPublicKey>; pem: string } {
  try {
    const pem = readFileSync(resolve(process.cwd(), publicKeyPath), "utf8");
    return { publicKey: createPublicKey(pem), pem };
  } catch (error) {
    throw keyMaterialError(
      `could not read/parse --public-key: ${error instanceof Error ? error.message : String(error)}`,
      "public_key.invalid"
    );
  }
}

function samePublicKey(left: string, right: string): boolean {
  if (left === right) {
    return true;
  }
  try {
    const canonicalLeft = createPublicKey(left).export({ type: "spki", format: "pem" }).toString();
    const canonicalRight = createPublicKey(right).export({ type: "spki", format: "pem" }).toString();
    return canonicalLeft === canonicalRight;
  } catch {
    return false;
  }
}

function selectPinnedTrustResolvers(pinnedKeyring: Keyring, flags: ParsedFlags): TrustResolvers {
  const pinnedKeyIds = keyIds(pinnedKeyring);
  const keyringPath = flags.keyring as string | undefined;
  if (keyringPath) {
    let requested: Keyring;
    try {
      requested = loadKeyring(resolve(process.cwd(), keyringPath));
    } catch (error) {
      throw keyMaterialError(
        `could not read --keyring: ${error instanceof Error ? error.message : String(error)}`,
        "showcase.approval_keyring_unreadable"
      );
    }
    const requestedIds = keyIds(requested);
    const selected = pinnedKeyring.keys.filter((key) =>
      requestedIds.has(key.algorithm === "webauthn" ? key.credential_id : key.key_id)
    );
    return selected.length > 0
      ? resolversForKeyring(keyringFromKeys(selected, keyringPath), [], pinnedKeyIds)
      : emptyTrustResolvers(pinnedKeyIds);
  }

  const publicKeyPath = flags.publicKey as string | undefined;
  if (publicKeyPath) {
    const { pem } = readPublicKeyFlag(publicKeyPath);
    const selected = pinnedKeyring.keys.filter((key) => key.algorithm === "ed25519" && samePublicKey(key.public_key, pem));
    return selected.length > 0
      ? resolversForKeyring(keyringFromKeys(selected, publicKeyPath), [], pinnedKeyIds)
      : emptyTrustResolvers(pinnedKeyIds);
  }

  return resolversForKeyring(pinnedKeyring, [], pinnedKeyIds);
}

// Build the (resolver, tierResolver) that VERIFY a signed approval token —
// used both to SUBMIT one (`showcase approve --approval-token`) and to READ an
// already-embedded one (`showcase status`). When use-cases.yml pins
// approval_trust, that anchor is authoritative and flags only narrow it. Without
// a pin, legacy flag-based trust remains supported but is surfaced as an
// advisory diagnostic.
function loadTrustResolvers(flags: ParsedFlags, context: ResolvedContext): TrustResolvers | null {
  const pinnedKeyring = loadPinnedApprovalTrustKeyring(context);
  if (pinnedKeyring) {
    return selectPinnedTrustResolvers(pinnedKeyring, flags);
  }

  const keyringPath = flags.keyring as string | undefined;
  if (keyringPath) {
    let keyring;
    try {
      keyring = loadKeyring(resolve(process.cwd(), keyringPath));
    } catch (error) {
      throw keyMaterialError(
        `could not read --keyring: ${error instanceof Error ? error.message : String(error)}`,
        "showcase.approval_keyring_unreadable"
      );
    }
    return {
      resolver: keyringResolver(keyring),
      tierResolver: keyringAssuranceTierResolver(keyring),
      webauthnCredentialResolver: keyringWebAuthnCredentialResolver(keyring),
      diagnostics: [callerSuppliedTrustDiagnostic()]
    };
  }
  const publicKeyPath = flags.publicKey as string | undefined;
  if (!publicKeyPath) {
    return null;
  }
  const { publicKey } = readPublicKeyFlag(publicKeyPath);
  return {
    resolver: singleKeyResolver(publicKey),
    // Operator explicitly nominated this single key as the trusted human signer:
    // treat it as trusted_host_user_presence so the floor is met. (The keyring
    // path is where per-key downgrades/revocations live.)
    tierResolver: () => AssuranceTier.TRUSTED_HOST_USER_PRESENCE,
    webauthnCredentialResolver: () => undefined,
    diagnostics: [callerSuppliedTrustDiagnostic()]
  };
}

function approvalTokenAnchorId(token: unknown): string | null {
  const signature = (token as { signature?: { key_id?: unknown; credential_id?: unknown } } | null)?.signature;
  const keyId = signature?.key_id;
  if (typeof keyId === "string") {
    return keyId;
  }
  const credentialId = signature?.credential_id;
  return typeof credentialId === "string" ? credentialId : null;
}

function approvalTokenUsesWebAuthn(token: unknown): boolean {
  return (token as { signature?: { alg?: unknown } } | null)?.signature?.alg === "webauthn";
}

function loadApprovalTokenBundle(flags: ParsedFlags, context: ResolvedContext): ApprovalTokenBundle | null {
  const tokenPath = flags.approvalToken as string | undefined;
  if (!tokenPath) {
    return null;
  }

  let approvalToken: unknown;
  try {
    approvalToken = JSON.parse(readFileSync(resolve(process.cwd(), tokenPath), "utf8"));
  } catch (error) {
    throw keyMaterialError(
      `could not read/parse --approval-token: ${error instanceof Error ? error.message : String(error)}`,
      "showcase.approval_token_unreadable"
    );
  }

  const trust = loadTrustResolvers(flags, context);
  if (!trust) {
    throw keyMaterialError(
      "verifying --approval-token needs trusted key material: pin approval_trust in use-cases.yml or pass --keyring <path> / --public-key <path>.",
      "showcase.approval_key_required"
    );
  }
  if (approvalTokenUsesWebAuthn(approvalToken) && !trust.pinnedKeyIds) {
    throw keyMaterialError(
      "webauthn approval tokens require a workspace-pinned approval_trust credential; caller-supplied keyrings cannot introduce WebAuthn trust.",
      "showcase.approval_webauthn_unpinned"
    );
  }
  const tokenKeyId = approvalTokenAnchorId(approvalToken);
  if (tokenKeyId && trust.pinnedKeyIds && !trust.pinnedKeyIds.has(tokenKeyId)) {
    throw keyMaterialError(
      `approval token signer '${tokenKeyId}' is not in pinned approval_trust.`,
      "showcase.approval_trust_anchor_unpinned"
    );
  }
  return { approvalToken, ...trust };
}

// EXIT PARITY (0.2.0): the process exit code an approval-bearing verb reports.
// A recorded approval is only an unqualified success when the resulting run is
// COMPLETE, its approval_state is a POSITIVE approval (approved /
// approved_with_known_gaps / not_required), AND the run itself ended in a
// passing outcome. Approving a rejected / still-pending / stale / failed /
// incomplete run must NOT read as exit 0 — otherwise a human sees green while
// the run did not actually pass (the acceptance re-run's false-success). This is
// single-sourced (the handler returns one exitCode used for BOTH --json and human
// renders), so the two modes are identical by construction.
function approvalExitCode(status: ReturnType<typeof startShowcaseRun>["status"]): number {
  const positiveApproval =
    status.approval_state === "approved" ||
    status.approval_state === "approved_with_known_gaps" ||
    status.approval_state === "not_required";
  const passingOutcome =
    status.run_outcome === "passed" || status.run_outcome === "passed_with_waivers";
  return status.complete && positiveApproval && passingOutcome ? 0 : 1;
}

// Non-writing port of the legacy `writeShowcaseResult`: wrap a showcase run
// result in the canonical envelope (ok=true, complete from the run status) and
// pair it with the verb's exit code instead of writing to stdout.
function showcaseResultOutput(
  command: string,
  result: ReturnType<typeof startShowcaseRun>,
  context: ResolvedContext,
  exitCode: number,
  // OPTIONAL envelope-ok override. Defaults to true so every existing verb's
  // envelope is byte-identical; approve passes (exitCode === 0) so a non-zero
  // (rejected/incomplete) approval reads ok:false in --json too, matching the
  // non-zero process exit.
  ok = true,
  diagnostics: CliDiagnostic[] = []
): CommandOutput {
  return {
    envelope: createCliResult(command, result, {
      ok,
      complete: result.status.complete,
      diagnostics,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }),
    exitCode
  };
}

// Non-writing port of the legacy `writeCaughtShowcaseError`: map a thrown core
// error to its diagnostic code/message and exit code (ledger damage -> 3, else
// 1), returning the envelope instead of writing.
function showcaseCaughtError(command: string, error: unknown): CommandOutput {
  const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
  return {
    envelope: errorEnvelope(command, code, error instanceof Error ? error.message : String(error)),
    exitCode: code === "showcase_ledger_damaged" ? 3 : 1
  };
}

// SECURITY: reject a user-supplied id that is not a canonical id BEFORE it can
// become a filesystem path segment (e.g. showcase-runs/<runId>/events.jsonl) or a
// ledger lookup key. Mirrors the legacy rejectUnsafeId/invalidIdExit: returns the
// stable UCM_INVALID_ID / exit-2 envelope, or null when the value is safe.
function rejectUnsafeId(command: string, paramName: string, value: string): CommandOutput | null {
  return isValidId(value)
    ? null
    : {
        envelope: errorEnvelope(
          command,
          "UCM_INVALID_ID",
          `Invalid ${paramName} '${value}': must be a canonical id (lowercase, no path separators, no '..').`
        ),
        exitCode: 2
      };
}

export const showcaseStartCommand: CliCommand = {
  path: ["showcase", "start"],
  command: "showcase.start",
  summary: "Start a showcase run from a plan file or an ad hoc selection.",
  flags: [
    ...workspaceFlags,
    { key: "planFile", name: "--plan-file", kind: "string", valueName: "<path>", summary: "Plan file to start the run from (inside the workspace)." },
    { key: "adhoc", name: "--adhoc", kind: "boolean", summary: "Build an ad hoc plan instead of reading --plan-file." },
    { key: "select", name: "--select", kind: "string", valueName: "<id>", summary: "Use-case id to select for the ad hoc plan." },
    { key: "audience", name: "--audience", kind: "string", valueName: "<audience>", summary: "Ad hoc plan audience (defaults to reviewer)." },
    { key: "timebox", name: "--timebox", kind: "integer", valueName: "<seconds>", summary: "Ad hoc plan timebox in seconds (defaults to 600)." },
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Ad hoc plan generation timestamp." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the start event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.start");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const planFile = flags.planFile as string | undefined;
    if (planFile) {
      const contained = containedPathOrError("showcase.start", contextResult.workspace_root, planFile);
      if (contained.kind === "error") {
        return { envelope: contained.envelope, exitCode: contained.exitCode };
      }
      const planPath = contained.path;
      try {
        const plan = loadPresentationPlanFile(planPath);
        const result = startShowcaseRun({
          context: contextResult,
          plan,
          controlMode: "agent_led",
          actorType: "agent",
          hostSurface: "codex.cli",
          idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:start-plan:${plan.plan_content_hash}`,
          recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:00:00.000Z"
        });
        return showcaseResultOutput("showcase.start", result, contextResult, 0);
      } catch (error) {
        return showcaseCaughtError("showcase.start", error);
      }
    }
    const selected = flags.select as string | undefined;
    if (!(flags.adhoc as boolean) || !selected) {
      return {
        envelope: errorEnvelope("showcase.start", "showcase.plan_required", "Only --adhoc --select is supported in P6."),
        exitCode: 2
      };
    }
    const matrix = loadUseCaseMatrix({ context: contextResult });
    const evidence = replayEvidence({ context: contextResult });
    const planResult = selectShowcasePlan({
      context: contextResult,
      matrix,
      evidence,
      request: {
        audience: (flags.audience as string | undefined) ?? "reviewer",
        timeboxSeconds: (flags.timebox as number | undefined) ?? 600,
        maxItems: 1,
        hostSurface: "codex.cli",
        requestedUseCaseIds: [selected],
        generatedAt: (flags.generatedAt as string | undefined) ?? "2026-06-25T12:00:00.000Z",
        freshnessEvaluatedAt: (flags.generatedAt as string | undefined) ?? "2026-06-25T12:00:00.000Z"
      }
    });
    if (!planResult.plan || !planResult.plan.selected_items.some((item) => item.use_case_id === selected)) {
      return {
        envelope: errorEnvelope("showcase.start", "showcase.selected_use_case_unavailable", "Selected use case was not available for an ad hoc plan."),
        exitCode: 1
      };
    }
    try {
      const result = startShowcaseRun({
        context: contextResult,
        plan: planResult.plan,
        controlMode: "agent_led",
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:start:${selected}:${Date.now()}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:00:00.000Z"
      });
      return showcaseResultOutput("showcase.start", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.start", error);
    }
  }
};

export const showcaseRecordObservationCommand: CliCommand = {
  path: ["showcase", "record-observation"],
  command: "showcase.record-observation",
  summary: "Append an observation to a showcase run plan item.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "item", name: "--item", kind: "string", required: true, valueName: "<id>", summary: "Plan item id." },
    { key: "text", name: "--text", kind: "string", required: true, valueName: "<text>", summary: "Observation text." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the observation event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.record-observation");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const planItemId = flags.item as string | undefined;
    const text = flags.text as string | undefined;
    if (!runId || !planItemId || !text) {
      return {
        envelope: errorEnvelope("showcase.record-observation", "cli_invalid_arguments", "Missing --run, --item, or --text."),
        exitCode: 2
      };
    }
    const invalidObservationId =
      rejectUnsafeId("showcase.record-observation", "--run", runId) ??
      rejectUnsafeId("showcase.record-observation", "--item", planItemId);
    if (invalidObservationId !== null) {
      return invalidObservationId;
    }
    try {
      const result = appendShowcaseObservation({
        context: contextResult,
        runId,
        planItemId,
        text,
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:observation:${runId}:${planItemId}:${text}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:01:00.000Z"
      });
      return showcaseResultOutput("showcase.record-observation", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.record-observation", error);
    }
  }
};

export const showcaseRecordVerdictCommand: CliCommand = {
  path: ["showcase", "record-verdict"],
  command: "showcase.record-verdict",
  summary: "Append a verdict to a showcase run plan item.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "item", name: "--item", kind: "string", required: true, valueName: "<id>", summary: "Plan item id." },
    { key: "verdict", name: "--verdict", kind: "string", required: true, valueName: "<verdict>", summary: "Verdict value." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the verdict event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.record-verdict");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const planItemId = flags.item as string | undefined;
    const verdict = flags.verdict as string | undefined;
    if (!runId || !planItemId || !verdict) {
      return {
        envelope: errorEnvelope("showcase.record-verdict", "cli_invalid_arguments", "Missing --run, --item, or --verdict."),
        exitCode: 2
      };
    }
    const invalidVerdictId =
      rejectUnsafeId("showcase.record-verdict", "--run", runId) ??
      rejectUnsafeId("showcase.record-verdict", "--item", planItemId);
    if (invalidVerdictId !== null) {
      return invalidVerdictId;
    }
    const status = replayShowcaseRun({ context: contextResult, runId });
    const item = status.items.find((candidate) => candidate.plan_item_id === planItemId);
    if (!item?.latest_observation_event_id) {
      return {
        envelope: errorEnvelope("showcase.record-verdict", "showcase.verdict_requires_observation", "Verdict requires a prior observation."),
        exitCode: 1
      };
    }
    try {
      const result = appendShowcaseVerdict({
        context: contextResult,
        runId,
        planItemId,
        verdict: verdict as Parameters<typeof appendShowcaseVerdict>[0]["verdict"],
        observationEventIds: [item.latest_observation_event_id],
        actorType: ((flags.actor as string | undefined) ?? "agent") as Parameters<typeof appendShowcaseVerdict>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:verdict:${runId}:${planItemId}:${verdict}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:02:00.000Z"
      });
      return showcaseResultOutput("showcase.record-verdict", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.record-verdict", error);
    }
  }
};

export const showcaseDecideCommand: CliCommand = {
  path: ["showcase", "decide"],
  command: "showcase.decide",
  summary: "Record a failure decision against a showcase verdict event.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "verdictEvent", name: "--verdict-event", kind: "string", required: true, valueName: "<event-id>", summary: "Verdict event id the decision targets." },
    { key: "decision", name: "--decision", kind: "string", required: true, valueName: "<decision>", summary: "Decision value." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the decision was made." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the decision event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.decide");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const verdictEventId = flags.verdictEvent as string | undefined;
    const decision = flags.decision as string | undefined;
    const reason = flags.reason as string | undefined;
    if (!runId || !verdictEventId || !decision || !reason) {
      return {
        envelope: errorEnvelope("showcase.decide", "cli_invalid_arguments", "Missing --run, --verdict-event, --decision, or --reason."),
        exitCode: 2
      };
    }
    const invalidDecideId = rejectUnsafeId("showcase.decide", "--run", runId);
    if (invalidDecideId !== null) {
      return invalidDecideId;
    }
    try {
      const result = appendShowcaseFailureDecision({
        context: contextResult,
        runId,
        verdictEventId,
        decision: decision as Parameters<typeof appendShowcaseFailureDecision>[0]["decision"],
        reason,
        actorType: ((flags.actor as string | undefined) ?? "agent") as Parameters<typeof appendShowcaseFailureDecision>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:decision:${runId}:${verdictEventId}:${decision}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:02:30.000Z"
      });
      return showcaseResultOutput("showcase.decide", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.decide", error);
    }
  }
};

export const showcasePauseCommand: CliCommand = {
  path: ["showcase", "pause"],
  command: "showcase.pause",
  summary: "Pause a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "reason", name: "--reason", kind: "string", valueName: "<text>", summary: "Pause reason (defaults to 'Paused by operator.')." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the pause event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.pause");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const reason = (flags.reason as string | undefined) ?? "Paused by operator.";
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.pause", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidPauseId = rejectUnsafeId("showcase.pause", "--run", runId);
    if (invalidPauseId !== null) {
      return invalidPauseId;
    }
    try {
      const result = pauseShowcaseRun({
        context: contextResult,
        runId,
        reason,
        actorType: ((flags.actor as string | undefined) ?? "agent") as Parameters<typeof pauseShowcaseRun>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:pause:${runId}:${reason}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:02:45.000Z"
      });
      return showcaseResultOutput("showcase.pause", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.pause", error);
    }
  }
};

export const showcaseResumeCommand: CliCommand = {
  path: ["showcase", "resume"],
  command: "showcase.resume",
  summary: "Resume a paused showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "reason", name: "--reason", kind: "string", valueName: "<text>", summary: "Resume reason (defaults to 'Resumed by operator.')." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the resume event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.resume");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const reason = (flags.reason as string | undefined) ?? "Resumed by operator.";
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.resume", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidResumeId = rejectUnsafeId("showcase.resume", "--run", runId);
    if (invalidResumeId !== null) {
      return invalidResumeId;
    }
    try {
      const result = resumeShowcaseRun({
        context: contextResult,
        runId,
        reason,
        actorType: ((flags.actor as string | undefined) ?? "agent") as Parameters<typeof resumeShowcaseRun>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:resume:${runId}:${reason}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:02:50.000Z"
      });
      return showcaseResultOutput("showcase.resume", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.resume", error);
    }
  }
};

export const showcaseFinishCommand: CliCommand = {
  path: ["showcase", "finish"],
  command: "showcase.finish",
  summary: "Finish a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the finish event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.finish");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.finish", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidFinishId = rejectUnsafeId("showcase.finish", "--run", runId);
    if (invalidFinishId !== null) {
      return invalidFinishId;
    }
    try {
      const result = finishShowcaseRun({
        context: contextResult,
        runId,
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:finish:${runId}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:03:00.000Z"
      });
      return showcaseResultOutput("showcase.finish", result, contextResult, result.status.run_outcome === "passed" ? 0 : 1);
    } catch (error) {
      return showcaseCaughtError("showcase.finish", error);
    }
  }
};

export const showcaseStatusCommand: CliCommand = {
  path: ["showcase", "status"],
  command: "showcase.status",
  summary: "Replay and report a showcase run's status.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "keyring", name: "--keyring", kind: "string", valueName: "<path>", summary: "Keyring to verify an embedded approval token, or narrow pinned approval_trust." },
    { key: "publicKey", name: "--public-key", kind: "string", valueName: "<path>", summary: "Single public key to verify an embedded approval token, or narrow pinned approval_trust." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.status");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.status", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidStatusId = rejectUnsafeId("showcase.status", "--run", runId);
    if (invalidStatusId !== null) {
      return invalidStatusId;
    }
    // Verifying an embedded signed approval token needs trusted key material.
    // A pinned approval_trust block supplies it without flags. Without either,
    // replay fails closed (a signed approval reads pending).
    let trust: TrustResolvers | null;
    try {
      trust = loadTrustResolvers(flags, contextResult);
    } catch (error) {
      return showcaseCaughtError("showcase.status", error);
    }
    const status = replayShowcaseRun({
      context: contextResult,
      runId,
      ...(trust
        ? {
            trustResolver: trust.resolver,
            trustTierResolver: trust.tierResolver,
            trustWebAuthnCredentialResolver: trust.webauthnCredentialResolver
          }
        : {})
    });
    return {
      envelope: createCliResult("showcase.status", status, {
        ok: true,
        complete: status.complete,
        diagnostics: trust?.diagnostics ?? [],
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      }),
      exitCode: 0
    };
  }
};

export const showcaseRequestApprovalCommand: CliCommand = {
  path: ["showcase", "request-approval"],
  command: "showcase.request-approval",
  summary: "Mint an unsigned approval request for a finished showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.request-approval");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.request-approval", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    const invalidRequestId = rejectUnsafeId("showcase.request-approval", "--run", runId);
    if (invalidRequestId !== null) {
      return invalidRequestId;
    }
    try {
      const binding = computeRunApprovalBinding({ context: contextResult, runId });
      const request = mintApprovalRequest({ binding });
      return { envelope: request, exitCode: 0 };
    } catch (error) {
      return showcaseCaughtError("showcase.request-approval", error);
    }
  }
};

export const showcaseApproveCommand: CliCommand = {
  path: ["showcase", "approve"],
  command: "showcase.approve",
  summary: "Record an approval for a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "statement", name: "--statement", kind: "string", required: true, valueName: "<text>", summary: "Approval statement." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent; --approval-token forces user)." },
    { key: "approvalToken", name: "--approval-token", kind: "string", valueName: "<path>", summary: "Signed approval token JSON from `uc approve-run` — the ONLY trusted human sign-off path (F3)." },
    { key: "keyring", name: "--keyring", kind: "string", valueName: "<path>", summary: "Public-key keyring that verifies --approval-token, or narrows pinned approval_trust." },
    { key: "publicKey", name: "--public-key", kind: "string", valueName: "<path>", summary: "Single public key that verifies --approval-token, or narrows pinned approval_trust." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the approval event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.approve");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const statement = flags.statement as string | undefined;
    if (!runId) {
      return {
        envelope: errorEnvelope("showcase.approve", "cli_invalid_arguments", "Missing --run."),
        exitCode: 2
      };
    }
    if (!statement) {
      return {
        envelope: errorEnvelope(
          "showcase.approve",
          "cli_invalid_arguments",
          "Missing --statement (required: the human-readable approval statement)."
        ),
        exitCode: 2
      };
    }
    const invalidApproveId = rejectUnsafeId("showcase.approve", "--run", runId);
    if (invalidApproveId !== null) {
      return invalidApproveId;
    }
    // F3 BLOCKER 1: a signed approval token turns this into the trusted human
    // sign-off path. The verify+append core independently re-checks the
    // signature, the live-run binding, the nonce burn, expiry, and the key's
    // keyring-bound assurance tier — trust is COMPUTED, never asserted here. A
    // signed token is by definition a USER sign-off, so it forces actorType=user.
    let approvalBundle: ApprovalTokenBundle | null;
    try {
      approvalBundle = loadApprovalTokenBundle(flags, contextResult);
    } catch (error) {
      return showcaseCaughtError("showcase.approve", error);
    }
    const actorType = (
      approvalBundle ? "user" : ((flags.actor as string | undefined) ?? "agent")
    ) as Parameters<typeof appendShowcaseApproval>[0]["actorType"];
    try {
      const result = appendShowcaseApproval({
        context: contextResult,
        runId,
        decision: "approved",
        actorType,
        hostSurface: "codex.cli",
        statement,
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:approve:${runId}:${statement}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:04:00.000Z",
        // SECURITY (F3): WITHOUT --approval-token these are all undefined, so the
        // CLI path carries no signed token — an agent driving `uc showcase
        // approve` still gets untrusted_automation and a user-required plan stays
        // pending. WITH --approval-token, the (token, resolver, tierResolver,
        // policy-derived floor) bundle drives the existing verify+append gate; the trusted key
        // material lives OUTSIDE the run ledger (pinned approval_trust, or
        // legacy --keyring / --public-key when no pin exists).
        ...(approvalBundle
          ? {
              approvalToken: approvalBundle.approvalToken as Parameters<typeof appendShowcaseApproval>[0]["approvalToken"],
              resolver: approvalBundle.resolver,
              tierResolver: approvalBundle.tierResolver,
              webauthnCredentialResolver: approvalBundle.webauthnCredentialResolver
            }
          : {})
      });
      // EXIT PARITY: derive the exit from the recorded run state — a rejected,
      // still-pending, stale, failed, or incomplete run is NOT an exit-0 success.
      const exitCode = approvalExitCode(result.status);
      return showcaseResultOutput(
        "showcase.approve",
        result,
        contextResult,
        exitCode,
        exitCode === 0,
        approvalBundle?.diagnostics ?? []
      );
    } catch (error) {
      return showcaseCaughtError("showcase.approve", error);
    }
  }
};

export const showcaseRejectCommand: CliCommand = {
  path: ["showcase", "reject"],
  command: "showcase.reject",
  summary: "Record a rejection for a showcase run.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "statement", name: "--statement", kind: "string", required: true, valueName: "<text>", summary: "Rejection statement." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to user)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the rejection event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.reject");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const statement = flags.statement as string | undefined;
    if (!runId || !statement) {
      return {
        envelope: errorEnvelope("showcase.reject", "cli_invalid_arguments", "Missing --run or --statement."),
        exitCode: 2
      };
    }
    const invalidRejectId = rejectUnsafeId("showcase.reject", "--run", runId);
    if (invalidRejectId !== null) {
      return invalidRejectId;
    }
    try {
      const result = rejectShowcaseApproval({
        context: contextResult,
        runId,
        actorType: ((flags.actor as string | undefined) ?? "user") as Parameters<typeof rejectShowcaseApproval>[0]["actorType"],
        hostSurface: "codex.cli",
        statement,
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:reject:${runId}:${statement}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:04:30.000Z"
        // SECURITY (F3): no signed token on this path -> untrusted_automation.
        // Trusted human sign-off comes ONLY from `uc approve-run`.
      });
      return showcaseResultOutput("showcase.reject", result, contextResult, 1);
    } catch (error) {
      return showcaseCaughtError("showcase.reject", error);
    }
  }
};

export const showcaseCorrectCommand: CliCommand = {
  path: ["showcase", "correct"],
  command: "showcase.correct",
  summary: "Correct a previously recorded showcase verdict.",
  flags: [
    ...workspaceFlags,
    { key: "run", name: "--run", kind: "string", required: true, valueName: "<id>", summary: "Showcase run id." },
    { key: "targetEvent", name: "--target-event", kind: "string", required: true, valueName: "<event-id>", summary: "Verdict event id to correct." },
    { key: "verdict", name: "--verdict", kind: "string", required: true, valueName: "<verdict>", summary: "Corrected verdict value." },
    { key: "reason", name: "--reason", kind: "string", required: true, valueName: "<text>", summary: "Why the verdict is being corrected." },
    { key: "actor", name: "--actor", kind: "string", valueName: "<type>", summary: "Actor type (defaults to agent)." },
    { key: "idempotencyKey", name: "--idempotency-key", kind: "string", valueName: "<key>", summary: "Idempotency key (defaults to a derived cli: key)." },
    { key: "recordedAt", name: "--recorded-at", kind: "string", valueName: "<iso>", summary: "Recorded-at timestamp for the correction event." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "showcase.correct");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const contextResult = context.context;
    const runId = flags.run as string | undefined;
    const targetEventId = flags.targetEvent as string | undefined;
    const correctedVerdict = flags.verdict as string | undefined;
    const reason = flags.reason as string | undefined;
    if (!runId || !targetEventId || !correctedVerdict || !reason) {
      return {
        envelope: errorEnvelope("showcase.correct", "cli_invalid_arguments", "Missing --run, --target-event, --verdict, or --reason."),
        exitCode: 2
      };
    }
    const invalidCorrectId = rejectUnsafeId("showcase.correct", "--run", runId);
    if (invalidCorrectId !== null) {
      return invalidCorrectId;
    }
    try {
      const result = correctShowcaseVerdict({
        context: contextResult,
        runId,
        targetEventId,
        correctedVerdict: correctedVerdict as Parameters<typeof correctShowcaseVerdict>[0]["correctedVerdict"],
        reason,
        actorType: ((flags.actor as string | undefined) ?? "agent") as Parameters<typeof correctShowcaseVerdict>[0]["actorType"],
        hostSurface: "codex.cli",
        idempotencyKey: (flags.idempotencyKey as string | undefined) ?? `cli:correct:${runId}:${targetEventId}:${correctedVerdict}`,
        recordedAt: (flags.recordedAt as string | undefined) ?? "2026-06-25T12:04:45.000Z"
      });
      return showcaseResultOutput("showcase.correct", result, contextResult, 0);
    } catch (error) {
      return showcaseCaughtError("showcase.correct", error);
    }
  }
};

export const showcaseCommands: CliCommand[] = [
  showcaseStartCommand,
  showcaseRecordObservationCommand,
  showcaseRecordVerdictCommand,
  showcaseDecideCommand,
  showcasePauseCommand,
  showcaseResumeCommand,
  showcaseFinishCommand,
  showcaseStatusCommand,
  showcaseRequestApprovalCommand,
  showcaseApproveCommand,
  showcaseRejectCommand,
  showcaseCorrectCommand
];
