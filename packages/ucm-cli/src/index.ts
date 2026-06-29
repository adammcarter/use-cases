#!/usr/bin/env node
import { accessSync, constants, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { createPrivateKey, createPublicKey } from "node:crypto";
import { isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  CiAuthority,
  HostName,
  HostProfile,
  ResolvedWorkspaceContext,
  UseCaseQuery,
  VerificationResultRecord
} from "@use-case-matrix/core";

type UcmCoreModule = typeof import("@use-case-matrix/core");

const {
  PUBLIC_SCHEMA_IDS,
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  createCliResult,
  getVersionInfo,
  loadDemoCapsules,
  loadHostProfile,
  loadUseCaseMatrix,
  migrateTestMatrix,
  planDemoCapsule,
  projectHostFiles,
  queryUseCases,
  renderCard,
  replayEvidence,
  resolveWorkspaceContext,
  runDemoCapsule,
  runHostConformance: runHostConformanceCore,
  runHostDoctor: runHostDoctorCore,
  replayShowcaseRun,
  selectShowcasePlan,
  selectWalkthroughPlan,
  appendShowcaseFailureDecision,
  appendShowcaseApproval,
  appendShowcaseObservation,
  appendShowcaseVerdict,
  correctShowcaseVerdict,
  finishShowcaseRun,
  loadPresentationPlanFile,
  mutateUseCaseMatrix,
  pauseShowcaseRun,
  rejectShowcaseApproval,
  resumeShowcaseRun,
  startShowcaseRun,
  toEvidenceAppendResult,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult,
  validateSkillAssets,
  validateFixtureWorkspace,
  inspectPackageArtifact,
  runBindCommand,
  runScanCommand,
  runProveCommand,
  runVerifyCommand,
  runValidateLedgerCommand,
  detectCiAuthority,
  singleKeyResolver,
  keyringPublicKeyResolverFromFile
} = await loadUcmCore();

const SUPPORTED_HOSTS: HostName[] = ["claude", "codex", "copilot", "opencode"];

async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@use-case-matrix/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../ucm-core/dist/index.js";
    return await import(bundledCoreSpecifier) as UcmCoreModule;
  }
}

function isMissingCorePackage(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ERR_MODULE_NOT_FOUND" && error.message.includes("@use-case-matrix/core");
}

export function runCli(argv: string[]): number {
  const normalizedArgv = argv[0] === "--" ? argv.slice(1) : argv;
  const wantsVersion = normalizedArgv.includes("--version") || normalizedArgv.includes("-v");
  const wantsJson = normalizedArgv.includes("--json");

  if (wantsVersion) {
    if (wantsJson) {
      process.stdout.write(`${JSON.stringify(createCliResult("version", getVersionInfo()))}\n`);
    } else {
      process.stdout.write(`${getVersionInfo().version}\n`);
    }
    return 0;
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "list" && wantsJson) {
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("schema.list", {
          schemas: PUBLIC_SCHEMA_IDS.map((id) => ({ id }))
        })
      )}\n`
    );
    return 0;
  }

  if (normalizedArgv[0] === "schema" && normalizedArgv[1] === "validate-fixtures" && wantsJson) {
    const fixture = valueAfter(normalizedArgv, "--fixture") ?? "tests/fixtures/workspaces/minimal-valid";
    const fixturePath = resolve(process.cwd(), fixture);
    const result = validateFixtureWorkspace(fixturePath);
    process.stdout.write(
      `${JSON.stringify(
        createCliResult(
          "schema.validate-fixtures",
          {
            fixture,
            validated_schema_ids: result.validated_schema_ids,
            expected_state: result.expected_state
          },
          {
            ok: result.ok,
            complete: result.complete,
            diagnostics: result.diagnostics,
            dataRoot: fixturePath
          }
        )
      )}\n`
    );
    return 0;
  }

  if (normalizedArgv[0] === "matrix" && normalizedArgv[1] === "validate" && wantsJson) {
    return runMatrixValidate(normalizedArgv);
  }

  if (normalizedArgv[0] === "matrix" && normalizedArgv[1] === "list" && wantsJson) {
    return runMatrixList(normalizedArgv);
  }

  if (normalizedArgv[0] === "matrix" && normalizedArgv[1] === "status" && wantsJson) {
    return runMatrixStatus(normalizedArgv);
  }

  if (normalizedArgv[0] === "matrix" && normalizedArgv[1] === "upsert" && wantsJson) {
    return runMatrixUpsert(normalizedArgv);
  }

  if (normalizedArgv[0] === "matrix" && normalizedArgv[1] === "remove" && wantsJson) {
    return runMatrixRemove(normalizedArgv);
  }

  if (normalizedArgv[0] === "plan" && normalizedArgv[1] === "showcase" && wantsJson) {
    return runPlan(normalizedArgv, "showcase");
  }

  if (normalizedArgv[0] === "plan" && normalizedArgv[1] === "walkthrough" && wantsJson) {
    return runPlan(normalizedArgv, "walkthrough");
  }

  if (normalizedArgv[0] === "plan" && normalizedArgv[1] === "cards" && wantsJson) {
    return runPlanCards(normalizedArgv);
  }

  if (normalizedArgv[0] === "capsule" && wantsJson) {
    return runCapsule(normalizedArgv);
  }

  if (normalizedArgv[0] === "evidence" && normalizedArgv[1] === "record" && wantsJson) {
    return runEvidenceRecord(normalizedArgv);
  }

  if (normalizedArgv[0] === "showcase" && wantsJson) {
    return runShowcase(normalizedArgv);
  }

  if (normalizedArgv[0] === "evidence" && normalizedArgv[1] === "status" && wantsJson) {
    return runEvidenceStatus(normalizedArgv);
  }

  if (normalizedArgv[0] === "evidence" && normalizedArgv[1] === "void" && wantsJson) {
    return runEvidenceVoid(normalizedArgv);
  }

  if (normalizedArgv[0] === "workflow" && normalizedArgv[1] === "set-mode" && wantsJson) {
    return runWorkflowSetMode(normalizedArgv);
  }

  if (normalizedArgv[0] === "workflow" && normalizedArgv[1] === "mode" && wantsJson) {
    return runWorkflowMode(normalizedArgv);
  }

  if (normalizedArgv[0] === "migrate" && wantsJson) {
    return runMigrate(normalizedArgv);
  }

  if (normalizedArgv[0] === "host" && wantsJson) {
    return runHost(normalizedArgv);
  }

  if (normalizedArgv[0] === "doctor" && normalizedArgv[1] === "skills" && wantsJson) {
    return runDoctorSkills(normalizedArgv);
  }

  if (normalizedArgv[0] === "doctor" && normalizedArgv[1] === "package" && wantsJson) {
    return runDoctorPackage(normalizedArgv);
  }

  if (normalizedArgv[0] === "doctor" && normalizedArgv[1] === "roots" && wantsJson) {
    return runDoctorRoots(normalizedArgv);
  }

  if (normalizedArgv[0] === "bind") {
    return runMarkerBind(normalizedArgv);
  }

  if (normalizedArgv[0] === "scan") {
    return runMarkerScan(normalizedArgv);
  }

  if (normalizedArgv[0] === "prove") {
    return runMarkerProve(normalizedArgv);
  }

  if (normalizedArgv[0] === "verify") {
    return runMarkerVerify(normalizedArgv);
  }

  if (normalizedArgv[0] === "validate-ledger") {
    return runMarkerValidateLedger(normalizedArgv);
  }

  process.stderr.write(
    `${JSON.stringify(
      createCliResult(
        "unknown",
        {},
        {
          ok: false,
          complete: false,
          diagnostics: [
            {
              code: "command.unknown",
              severity: "error",
              message: "No supported P1 command was provided. Try --version --json or schema list --json.",
              source_path: null,
              json_pointer: null,
              entity_id: null,
              related_ids: []
            }
          ]
        }
      )
    )}\n`
  );
  return 2;
}

function runEvidenceRecord(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "evidence.record");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const context = contextResult;
  const useCaseId = valueAfter(argv, "--use-case");
  if (!useCaseId) {
    return writeError("evidence.record", "evidence.use_case.required", "Missing --use-case.");
  }
  const matrix = loadUseCaseMatrix({ context });
  const resolved = matrix.resolveUseCase(useCaseId);
  if (resolved.kind !== "resolved") {
    return writeError("evidence.record", "evidence.use_case.unresolved", `Use case '${useCaseId}' is ${resolved.kind}.`);
  }
  const kind = valueAfter(argv, "--kind") ?? "manual_observation";
  const result = valueAfter(argv, "--result") ?? "observed";
  const append = appendEvidenceEvent({
    context,
    idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:${useCaseId}:${kind}:${result}`,
    target: {
      use_case_id: useCaseId,
      use_case_semantic_hash: resolved.useCase.semanticHash
    },
    kind: kind as Parameters<typeof appendEvidenceEvent>[0]["kind"],
    result: result as Parameters<typeof appendEvidenceEvent>[0]["result"],
    summary: valueAfter(argv, "--summary") ?? `Recorded ${kind} evidence for ${useCaseId}.`,
    actorType: "agent",
    hostSurface: "codex.cli"
  });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("evidence.record", toEvidenceAppendResult(append), {
        ok: true,
        complete: true,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  return 0;
}

function runEvidenceVoid(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "evidence.void");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const evidenceId = valueAfter(argv, "--evidence");
  const expectedHead = valueAfter(argv, "--expected-head");
  const reason = valueAfter(argv, "--reason");
  if (!evidenceId || !expectedHead || !reason) {
    return writeError("evidence.void", "cli_invalid_arguments", "Missing --evidence, --expected-head, or --reason.");
  }
  try {
    const append = appendEvidenceVoidEvent({
      context: contextResult,
      evidenceId,
      expectedHeadEventId: expectedHead,
      reason,
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:void:${evidenceId}:${expectedHead}`,
      actorType: "agent",
      hostSurface: "codex.cli"
    });
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("evidence.void", toEvidenceAppendResult(append), {
          ok: true,
          complete: true,
          workspaceRoot: contextResult.workspace_root,
          dataRoot: contextResult.data_root,
          componentId: contextResult.component_id
        })
      )}\n`
    );
    return 0;
  } catch (error) {
    const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
    const exitCode = code === "evidence_expected_head_mismatch" ? 1 : code === "evidence_ledger_damaged" ? 3 : 6;
    return writeError("evidence.void", code, error instanceof Error ? error.message : String(error), exitCode);
  }
}

function runEvidenceStatus(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "evidence.status");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const context = contextResult;
  const snapshot = replayEvidence({ context });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("evidence.status", toEvidenceStatusResult(snapshot), {
        ok: snapshot.complete,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  return snapshot.complete ? 0 : 1;
}

function runMatrixValidate(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "matrix.validate");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const context = contextResult;
  const snapshot = loadUseCaseMatrix({ context });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("matrix.validate", toMatrixValidationResult(snapshot), {
        ok: true,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  return snapshot.complete ? 0 : 1;
}

function runMatrixList(argv: string[]): number {
  const strict = argv.includes("--strict");
  const contextResult = contextFromArgs(argv, "matrix.list");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const context = contextResult;
  const snapshot = loadUseCaseMatrix({ context });
  const selected = queryUseCases(snapshot, {
    valueTiers: valuesAfter(argv, "--value") as UseCaseQuery["valueTiers"],
    journeyRoles: valuesAfter(argv, "--journey-role") as UseCaseQuery["journeyRoles"],
    lifecycles: valuesAfter(argv, "--lifecycle") as UseCaseQuery["lifecycles"],
    hostSurfaces: valuesAfter(argv, "--host") as UseCaseQuery["hostSurfaces"],
    tagsAny: valuesAfter(argv, "--tag"),
    changedPaths: valuesAfter(argv, "--changed-path")
  });
  const ok = strict ? snapshot.complete : true;
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("matrix.list", toMatrixListResult(snapshot, selected), {
        ok,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  return ok ? 0 : 3;
}

function runMatrixStatus(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "matrix.status");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const matrix = loadUseCaseMatrix({ context: contextResult });
  const evidence = replayEvidence({ context: contextResult });
  const data = {
    schema_version: 1,
    complete: matrix.complete && evidence.complete,
    matrix: toMatrixValidationResult(matrix),
    evidence: toEvidenceStatusResult(evidence)
  };
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("matrix.status", data, {
        ok: data.complete,
        complete: data.complete,
        diagnostics: [...matrix.diagnostics, ...evidence.diagnostics],
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return data.complete ? 0 : 1;
}

function runMatrixUpsert(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "matrix.upsert");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const targetFile = valueAfter(argv, "--file");
  const useCaseJson = valueAfter(argv, "--use-case-json");
  if (!targetFile || !useCaseJson) {
    return writeError("matrix.upsert", "cli_invalid_arguments", "Missing --file or --use-case-json.");
  }
  let useCase: Record<string, unknown>;
  try {
    useCase = JSON.parse(useCaseJson) as Record<string, unknown>;
  } catch (error) {
    return writeError("matrix.upsert", "matrix.mutation_invalid_json", error instanceof Error ? error.message : String(error));
  }
  const result = mutateUseCaseMatrix({
    context: contextResult,
    operation: "upsert",
    targetFile,
    useCase,
    expectedSemanticHash: valueAfter(argv, "--expected-hash") ?? undefined,
    actor: "agent"
  });
  return writeMutationResult("matrix.upsert", result, contextResult);
}

function runMatrixRemove(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "matrix.remove");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const useCaseId = valueAfter(argv, "--use-case");
  const reason = valueAfter(argv, "--reason");
  if (!useCaseId || !reason) {
    return writeError("matrix.remove", "cli_invalid_arguments", "Missing --use-case or --reason.");
  }
  const result = mutateUseCaseMatrix({
    context: contextResult,
    operation: "remove",
    useCaseId,
    reason,
    expectedSemanticHash: valueAfter(argv, "--expected-hash") ?? undefined,
    actor: "agent"
  });
  return writeMutationResult("matrix.remove", result, contextResult);
}

function writeMutationResult(
  command: string,
  result: ReturnType<typeof mutateUseCaseMatrix>,
  context: ResolvedWorkspaceContext
): number {
  const ok = result.status !== "blocked";
  process.stdout.write(
    `${JSON.stringify(
      createCliResult(command, result, {
        ok,
        complete: ok,
        diagnostics: result.diagnostics,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  if (ok) {
    return 0;
  }
  const pathEscape = result.diagnostics.some((item) => item.code === "matrix.mutation_path_escape");
  return pathEscape ? 4 : 1;
}

function runPlan(argv: string[], mode: "showcase" | "walkthrough"): number {
  const contextResult = contextFromArgs(argv, `plan.${mode}`);
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const matrix = loadUseCaseMatrix({ context: contextResult });
  const evidence = replayEvidence({ context: contextResult });
  const request = {
    audience: valueAfter(argv, "--audience") ?? "reviewer",
    timeboxSeconds: numberAfter(argv, "--timebox") ?? (mode === "showcase" ? 600 : 1800),
    maxItems: numberAfter(argv, "--max-items"),
    hostSurface: (valueAfter(argv, "--host") ?? "unknown") as Parameters<typeof selectShowcasePlan>[0]["request"]["hostSurface"],
    changedPaths: valuesAfter(argv, "--changed-path"),
    generatedAt: valueAfter(argv, "--generated-at"),
    strict: argv.includes("--strict")
  };
  const result =
    mode === "showcase"
      ? selectShowcasePlan({ context: contextResult, matrix, evidence, request })
      : selectWalkthroughPlan({ context: contextResult, matrix, evidence, request });
  const ok = result.outcome !== "integrity_blocked";
  const complete = result.plan?.complete ?? (result.outcome === "no_eligible_items" && matrix.complete && evidence.complete);
  process.stdout.write(
    `${JSON.stringify(
      createCliResult(`plan.${mode}`, result, {
        ok,
        complete,
        diagnostics: [...matrix.diagnostics, ...evidence.diagnostics],
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  if (result.outcome === "integrity_blocked") {
    return 3;
  }
  if (result.outcome === "no_eligible_items") {
    return 1;
  }
  return 0;
}

function runPlanCards(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "plan.cards");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const planFile = valueAfter(argv, "--plan-file");
  if (!planFile) {
    return writeError("plan.cards", "cli_invalid_arguments", "Missing --plan-file.");
  }
  const planPath = isAbsolute(planFile) ? planFile : resolve(contextResult.workspace_root, planFile);
  try {
    const plan = loadPresentationPlanFile(planPath);
    const data = {
      schema_version: 1,
      plan_id: plan.plan_id,
      cards: plan.selected_items.map((item) => ({
        plan_item_id: item.plan_item_id,
        use_case_id: item.use_case_id,
        presentation_format: item.presentation_format,
        text: renderCard(item)
      }))
    };
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("plan.cards", data, {
          ok: true,
          complete: true,
          workspaceRoot: contextResult.workspace_root,
          dataRoot: contextResult.data_root,
          componentId: contextResult.component_id
        })
      )}\n`
    );
    return 0;
  } catch (error) {
    const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
    return writeError("plan.cards", code, error instanceof Error ? error.message : String(error), 1);
  }
}

function runCapsule(argv: string[]): number {
  const action = argv[1];
  if (action === "validate") {
    return runCapsuleValidate(argv);
  }
  if (action === "list") {
    return runCapsuleList(argv);
  }
  if (action === "plan") {
    return runCapsulePlan(argv);
  }
  if (action === "run") {
    return runCapsuleRun(argv);
  }
  return writeError("capsule.unknown", "command.unknown", "Unknown capsule command.");
}

function runCapsuleValidate(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "capsule.validate");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const snapshot = loadDemoCapsules({ context: contextResult });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("capsule.validate", snapshot, {
        ok: snapshot.complete,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return snapshot.complete ? 0 : 1;
}

function runCapsuleList(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "capsule.list");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const snapshot = loadDemoCapsules({ context: contextResult });
  const data = {
    schema_version: 1,
    complete: snapshot.complete,
    capsules: snapshot.capsules.map((entry) => ({
      capsule_id: entry.capsule.capsule_id,
      title: entry.capsule.title,
      mode: entry.capsule.mode,
      audience: entry.capsule.audience,
      timebox_seconds: entry.capsule.timebox_seconds,
      item_count: entry.capsule.items.length,
      path: entry.path,
      semantic_hash: entry.semantic_hash
    }))
  };
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("capsule.list", data, {
        ok: true,
        complete: snapshot.complete,
        diagnostics: snapshot.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runCapsulePlan(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "capsule.plan");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const capsuleId = valueAfter(argv, "--capsule");
  if (!capsuleId) {
    return writeError("capsule.plan", "cli_invalid_arguments", "Missing --capsule.");
  }
  const result = planDemoCapsule({ context: contextResult, capsuleId });
  const ok = result.outcome === "generated";
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("capsule.plan", result, {
        ok,
        complete: result.outcome === "generated" && (result.plan_result?.plan?.complete ?? false),
        diagnostics: result.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return result.outcome === "generated" ? 0 : result.outcome === "integrity_blocked" ? 3 : 1;
}

function runCapsuleRun(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "capsule.run");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const capsuleId = valueAfter(argv, "--capsule");
  if (!capsuleId) {
    return writeError("capsule.run", "cli_invalid_arguments", "Missing --capsule.");
  }
  try {
    const result = runDemoCapsule({
      context: contextResult,
      capsuleId,
      executeCommands: argv.includes("--execute-commands"),
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? undefined,
      recordedAt: valueAfter(argv, "--recorded-at") ?? undefined,
      commandTimeoutMs: numberAfter(argv, "--command-timeout-ms") ?? undefined
    });
    return writeCapsuleRunResult(result, contextResult);
  } catch (error) {
    const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
    return writeError("capsule.run", code, error instanceof Error ? error.message : String(error), 1);
  }
}

function writeCapsuleRunResult(
  result: ReturnType<typeof runDemoCapsule>,
  context: ResolvedWorkspaceContext
): number {
  const ok = result.outcome !== "blocked";
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("capsule.run", result, {
        ok,
        complete: result.complete,
        diagnostics: result.diagnostics,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  if (!ok) {
    return result.diagnostics.some((item) => item.code === "capsule.command_cwd_escape") ? 4 : 1;
  }
  return result.command_results.some((item) => !item.matched_expected_exit_code) ? 1 : 0;
}

function runShowcase(argv: string[]): number {
  const action = argv[1];
  if (action === "start") {
    return runShowcaseStart(argv);
  }
  if (action === "record-observation") {
    return runShowcaseObservation(argv);
  }
  if (action === "record-verdict") {
    return runShowcaseVerdict(argv);
  }
  if (action === "decide") {
    return runShowcaseDecide(argv);
  }
  if (action === "pause") {
    return runShowcasePause(argv);
  }
  if (action === "resume") {
    return runShowcaseResume(argv);
  }
  if (action === "finish") {
    return runShowcaseFinish(argv);
  }
  if (action === "status") {
    return runShowcaseStatus(argv);
  }
  if (action === "approve") {
    return runShowcaseApprove(argv);
  }
  if (action === "reject") {
    return runShowcaseReject(argv);
  }
  if (action === "correct") {
    return runShowcaseCorrect(argv);
  }
  return writeError("showcase.unknown", "command.unknown", "Unknown showcase command.");
}

function runShowcaseStart(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.start");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const planFile = valueAfter(argv, "--plan-file");
  if (planFile) {
    const planPath = isAbsolute(planFile) ? planFile : resolve(contextResult.workspace_root, planFile);
    try {
      const plan = loadPresentationPlanFile(planPath);
      const result = startShowcaseRun({
        context: contextResult,
        plan,
        controlMode: "agent_led",
        actorType: "agent",
        hostSurface: "codex.cli",
        idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:start-plan:${plan.plan_content_hash}`,
        recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:00:00.000Z"
      });
      return writeShowcaseResult("showcase.start", result, contextResult, 0);
    } catch (error) {
      return writeCaughtShowcaseError("showcase.start", error);
    }
  }
  const selected = valueAfter(argv, "--select");
  if (!argv.includes("--adhoc") || !selected) {
    return writeError("showcase.start", "showcase.plan_required", "Only --adhoc --select is supported in P6.");
  }
  const matrix = loadUseCaseMatrix({ context: contextResult });
  const evidence = replayEvidence({ context: contextResult });
  const planResult = selectShowcasePlan({
    context: contextResult,
    matrix,
    evidence,
    request: {
      audience: valueAfter(argv, "--audience") ?? "reviewer",
      timeboxSeconds: numberAfter(argv, "--timebox") ?? 600,
      maxItems: 1,
      hostSurface: "codex.cli",
      requestedUseCaseIds: [selected],
      generatedAt: valueAfter(argv, "--generated-at") ?? "2026-06-25T12:00:00.000Z",
      freshnessEvaluatedAt: valueAfter(argv, "--generated-at") ?? "2026-06-25T12:00:00.000Z"
    }
  });
  if (!planResult.plan || !planResult.plan.selected_items.some((item) => item.use_case_id === selected)) {
    return writeError("showcase.start", "showcase.selected_use_case_unavailable", "Selected use case was not available for an ad hoc plan.", 1);
  }
  try {
    const result = startShowcaseRun({
      context: contextResult,
      plan: planResult.plan,
      controlMode: "agent_led",
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:start:${selected}:${Date.now()}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:00:00.000Z"
    });
    return writeShowcaseResult("showcase.start", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.start", error);
  }
}

function runShowcaseObservation(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.record-observation");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const planItemId = valueAfter(argv, "--item");
  const text = valueAfter(argv, "--text");
  if (!runId || !planItemId || !text) {
    return writeError("showcase.record-observation", "cli_invalid_arguments", "Missing --run, --item, or --text.");
  }
  try {
    const result = appendShowcaseObservation({
      context: contextResult,
      runId,
      planItemId,
      text,
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:observation:${runId}:${planItemId}:${text}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:01:00.000Z"
    });
    return writeShowcaseResult("showcase.record-observation", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.record-observation", error);
  }
}

function runShowcaseVerdict(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.record-verdict");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const planItemId = valueAfter(argv, "--item");
  const verdict = valueAfter(argv, "--verdict");
  if (!runId || !planItemId || !verdict) {
    return writeError("showcase.record-verdict", "cli_invalid_arguments", "Missing --run, --item, or --verdict.");
  }
  const status = replayShowcaseRun({ context: contextResult, runId });
  const item = status.items.find((candidate) => candidate.plan_item_id === planItemId);
  if (!item?.latest_observation_event_id) {
    return writeError("showcase.record-verdict", "showcase.verdict_requires_observation", "Verdict requires a prior observation.", 1);
  }
  try {
    const result = appendShowcaseVerdict({
      context: contextResult,
      runId,
      planItemId,
      verdict: verdict as Parameters<typeof appendShowcaseVerdict>[0]["verdict"],
      observationEventIds: [item.latest_observation_event_id],
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseVerdict>[0]["actorType"],
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:verdict:${runId}:${planItemId}:${verdict}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:00.000Z"
    });
    return writeShowcaseResult("showcase.record-verdict", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.record-verdict", error);
  }
}

function runShowcaseDecide(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.decide");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const verdictEventId = valueAfter(argv, "--verdict-event");
  const decision = valueAfter(argv, "--decision");
  const reason = valueAfter(argv, "--reason");
  if (!runId || !verdictEventId || !decision || !reason) {
    return writeError("showcase.decide", "cli_invalid_arguments", "Missing --run, --verdict-event, --decision, or --reason.");
  }
  try {
    const result = appendShowcaseFailureDecision({
      context: contextResult,
      runId,
      verdictEventId,
      decision: decision as Parameters<typeof appendShowcaseFailureDecision>[0]["decision"],
      reason,
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseFailureDecision>[0]["actorType"],
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:decision:${runId}:${verdictEventId}:${decision}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:30.000Z"
    });
    return writeShowcaseResult("showcase.decide", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.decide", error);
  }
}

function runShowcasePause(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.pause");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const reason = valueAfter(argv, "--reason") ?? "Paused by operator.";
  if (!runId) {
    return writeError("showcase.pause", "cli_invalid_arguments", "Missing --run.");
  }
  try {
    const result = pauseShowcaseRun({
      context: contextResult,
      runId,
      reason,
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof pauseShowcaseRun>[0]["actorType"],
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:pause:${runId}:${reason}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:45.000Z"
    });
    return writeShowcaseResult("showcase.pause", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.pause", error);
  }
}

function runShowcaseResume(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.resume");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const reason = valueAfter(argv, "--reason") ?? "Resumed by operator.";
  if (!runId) {
    return writeError("showcase.resume", "cli_invalid_arguments", "Missing --run.");
  }
  try {
    const result = resumeShowcaseRun({
      context: contextResult,
      runId,
      reason,
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof resumeShowcaseRun>[0]["actorType"],
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:resume:${runId}:${reason}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:02:50.000Z"
    });
    return writeShowcaseResult("showcase.resume", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.resume", error);
  }
}

function runShowcaseFinish(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.finish");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  if (!runId) {
    return writeError("showcase.finish", "cli_invalid_arguments", "Missing --run.");
  }
  try {
    const result = finishShowcaseRun({
      context: contextResult,
      runId,
      actorType: "agent",
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:finish:${runId}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:03:00.000Z"
    });
    return writeShowcaseResult("showcase.finish", result, contextResult, result.status.run_outcome === "passed" ? 0 : 1);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.finish", error);
  }
}

function runShowcaseStatus(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.status");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  if (!runId) {
    return writeError("showcase.status", "cli_invalid_arguments", "Missing --run.");
  }
  const status = replayShowcaseRun({ context: contextResult, runId });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("showcase.status", status, {
        ok: true,
        complete: status.complete,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runShowcaseApprove(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.approve");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const statement = valueAfter(argv, "--statement");
  if (!runId || !statement) {
    return writeError("showcase.approve", "cli_invalid_arguments", "Missing --run or --statement.");
  }
  try {
    const result = appendShowcaseApproval({
      context: contextResult,
      runId,
      decision: "approved",
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof appendShowcaseApproval>[0]["actorType"],
      hostSurface: "codex.cli",
      statement,
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:approve:${runId}:${statement}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:00.000Z",
      authority: { kind: "untrusted_automation" }
    });
    return writeShowcaseResult("showcase.approve", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.approve", error);
  }
}

function runShowcaseReject(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.reject");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const statement = valueAfter(argv, "--statement");
  if (!runId || !statement) {
    return writeError("showcase.reject", "cli_invalid_arguments", "Missing --run or --statement.");
  }
  try {
    const result = rejectShowcaseApproval({
      context: contextResult,
      runId,
      actorType: (valueAfter(argv, "--actor") ?? "user") as Parameters<typeof rejectShowcaseApproval>[0]["actorType"],
      hostSurface: "codex.cli",
      statement,
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:reject:${runId}:${statement}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:30.000Z",
      authority: { kind: "untrusted_automation" }
    });
    return writeShowcaseResult("showcase.reject", result, contextResult, 1);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.reject", error);
  }
}

function runShowcaseCorrect(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "showcase.correct");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const runId = valueAfter(argv, "--run");
  const targetEventId = valueAfter(argv, "--target-event");
  const correctedVerdict = valueAfter(argv, "--verdict");
  const reason = valueAfter(argv, "--reason");
  if (!runId || !targetEventId || !correctedVerdict || !reason) {
    return writeError("showcase.correct", "cli_invalid_arguments", "Missing --run, --target-event, --verdict, or --reason.");
  }
  try {
    const result = correctShowcaseVerdict({
      context: contextResult,
      runId,
      targetEventId,
      correctedVerdict: correctedVerdict as Parameters<typeof correctShowcaseVerdict>[0]["correctedVerdict"],
      reason,
      actorType: (valueAfter(argv, "--actor") ?? "agent") as Parameters<typeof correctShowcaseVerdict>[0]["actorType"],
      hostSurface: "codex.cli",
      idempotencyKey: valueAfter(argv, "--idempotency-key") ?? `cli:correct:${runId}:${targetEventId}:${correctedVerdict}`,
      recordedAt: valueAfter(argv, "--recorded-at") ?? "2026-06-25T12:04:45.000Z"
    });
    return writeShowcaseResult("showcase.correct", result, contextResult, 0);
  } catch (error) {
    return writeCaughtShowcaseError("showcase.correct", error);
  }
}

function writeShowcaseResult(
  command: string,
  result: ReturnType<typeof startShowcaseRun>,
  context: ReturnType<typeof resolveWorkspaceContext>,
  exitCode: number
): number {
  process.stdout.write(
    `${JSON.stringify(
      createCliResult(command, result, {
        ok: true,
        complete: result.status.complete,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
  return exitCode;
}

function writeCaughtShowcaseError(command: string, error: unknown): number {
  const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
  return writeError(command, code, error instanceof Error ? error.message : String(error), code === "showcase_ledger_damaged" ? 3 : 1);
}

function runMigrate(argv: string[]): number {
  if (argv[1] !== "test-matrix") {
    return writeError("migrate.unknown", "command.unknown", "Unknown migrate command.");
  }
  const contextResult = contextFromArgs(argv, "migrate.test-matrix");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const sourcePath = valueAfter(argv, "--source");
  if (!sourcePath) {
    return writeError("migrate.test-matrix", "migration_source_required", "Missing --source.");
  }
  const selectedModes = [
    argv.includes("--dry-run") ? "dry_run" : null,
    argv.includes("--write") ? "write" : null
  ].filter((value): value is "dry_run" | "write" => value !== null);
  if (selectedModes.length > 1) {
    return writeError("migrate.test-matrix", "migration_mode_conflict", "Use only one of --dry-run or --write.");
  }
  const mode = selectedModes[0] ?? "dry_run";
  try {
    const result = migrateTestMatrix({
      context: contextResult,
      sourcePath,
      outDir: valueAfter(argv, "--out") ?? undefined,
      mode
    });
    const hasConflict = result.would_write.some((operation) => operation.action === "conflict");
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("migrate.test-matrix", result, {
          ok: !hasConflict,
          complete: result.warnings.length === 0 && !hasConflict,
          diagnostics: migrationDiagnostics(result),
          workspaceRoot: contextResult.workspace_root,
          dataRoot: contextResult.data_root,
          componentId: contextResult.component_id
        })
      )}\n`
    );
    return hasConflict ? 1 : 0;
  } catch (error) {
    const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
    const exitCode = code === "migration_unsafe_output_path" || code === "migration_unsafe_source_path" ? 4 : 1;
    return writeError("migrate.test-matrix", code, error instanceof Error ? error.message : String(error), exitCode);
  }
}

function runHost(argv: string[]): number {
  const action = argv[1];
  if (action === "doctor") {
    return runHostDoctor(argv);
  }
  if (action === "project") {
    return runHostProject(argv);
  }
  if (action === "conformance") {
    return runHostConformance(argv);
  }
  return writeError("host.unknown", "command.unknown", "Unknown host command.");
}

function runHostDoctor(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "host.doctor");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const profileResult = profileFromArgs(argv, contextResult.plugin_root, "host.doctor");
  if (profileResult.exitCode !== undefined) {
    return profileResult.exitCode;
  }
  const result = runHostDoctorCore({ context: contextResult, profile: profileResult.profile });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("host.doctor", result, {
        ok: true,
        complete: true,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runHostProject(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "host.project");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const profileResult = profileFromArgs(argv, contextResult.plugin_root, "host.project");
  if (profileResult.exitCode !== undefined) {
    return profileResult.exitCode;
  }
  const selectedModes = [
    argv.includes("--dry-run") ? "dry-run" : null,
    argv.includes("--write") ? "write" : null,
    argv.includes("--revert") ? "revert" : null
  ].filter((value): value is "dry-run" | "write" | "revert" => value !== null);
  if (selectedModes.length !== 1) {
    return writeError("host.project", "host.project_mode_required", "Use exactly one of --dry-run, --write, or --revert.");
  }
  const mode = selectedModes[0];
  const result = projectHostFiles({ context: contextResult, profile: profileResult.profile, mode });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("host.project", result, {
        ok: result.complete,
        complete: result.complete,
        diagnostics: result.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return result.complete ? 0 : 1;
}

function runHostConformance(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "host.conformance");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  if (argv.includes("--all")) {
    const hosts = SUPPORTED_HOSTS.map((host) => {
      const profile = loadHostProfile({ pluginRoot: contextResult.plugin_root, host });
      if (!profile.profile) {
        return {
          schema_version: 1,
          host,
          complete: false,
          diagnostics: profile.diagnostics
        };
      }
      return runHostConformanceCore({ context: contextResult, profile: profile.profile });
    });
    const diagnostics = hosts.flatMap((host) => "diagnostics" in host ? host.diagnostics : []);
    const hasBlockingDiagnostics = diagnostics.some((diagnostic) => diagnostic.severity === "error");
    const failedExecutableSmokes = hosts.filter(
      (host) => "executable_smoke" in host && host.executable_smoke.status === "failed"
    ).length;
    const notRunExecutableSmokes = hosts.filter(
      (host) => "executable_smoke" in host && host.executable_smoke.status === "not_run"
    ).length;
    const data = {
      schema_version: 1,
      complete: !hasBlockingDiagnostics,
      hosts,
      summary: {
        total_hosts: SUPPORTED_HOSTS.length,
        static_conformant: hosts.filter(
          (host) => "checks" in host && hostStaticChecksPass(host.checks)
        ).length,
        executable_smoke_passed: hosts.filter(
          (host) => "executable_smoke" in host && host.executable_smoke.status === "passed"
        ).length,
        executable_smoke_failed: failedExecutableSmokes,
        executable_smoke_not_run: notRunExecutableSmokes
      }
    };
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("host.conformance", data, {
          ok: !hasBlockingDiagnostics,
          complete: !hasBlockingDiagnostics,
          diagnostics,
          workspaceRoot: contextResult.workspace_root,
          dataRoot: contextResult.data_root,
          componentId: contextResult.component_id
        })
      )}\n`
    );
    return hasBlockingDiagnostics ? 1 : 0;
  }
  const profileResult = profileFromArgs(argv, contextResult.plugin_root, "host.conformance");
  if (profileResult.exitCode !== undefined) {
    return profileResult.exitCode;
  }
  const result = runHostConformanceCore({ context: contextResult, profile: profileResult.profile });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("host.conformance", result, {
        ok: !hasBlockingHostDiagnostics(result.diagnostics),
        complete: !hasBlockingHostDiagnostics(result.diagnostics),
        diagnostics: result.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return hasBlockingHostDiagnostics(result.diagnostics) ? 1 : 0;
}

function hasBlockingHostDiagnostics(diagnostics: Array<{ severity: string }>): boolean {
  return diagnostics.some((diagnostic) => diagnostic.severity === "error");
}

function hostStaticChecksPass(checks: Array<{ id: string; result: string }>): boolean {
  const staticChecks = checks.filter((check) => check.id === "projected_files_match_manifest" || check.id === "canonical_skill_hashes_match");
  return staticChecks.length > 0 && staticChecks.every((check) => check.result === "pass");
}

function profileFromArgs(
  argv: string[],
  pluginRoot: string,
  command: string
): { profile: HostProfile; exitCode?: undefined } | { profile?: undefined; exitCode: number } {
  const host = valueAfter(argv, "--host");
  if (!host) {
    return { exitCode: writeError(command, "host.required", "Missing --host.") };
  }
  const result = loadHostProfile({ pluginRoot, host: host as Parameters<typeof loadHostProfile>[0]["host"] });
  if (!result.profile) {
    return { exitCode: writeError(command, "host.profile_unavailable", result.diagnostics[0]?.message ?? "Host profile unavailable.", 1) };
  }
  return { profile: result.profile };
}

function migrationDiagnostics(result: ReturnType<typeof migrateTestMatrix>) {
  return result.warnings.map((warning) => ({
    code: warning.code,
    severity: "warning" as const,
    message: warning.message,
    source_path: warning.row_ref,
    json_pointer: null,
    entity_id: null,
    related_ids: []
  }));
}

function runWorkflowMode(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "workflow.get-mode");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const mode = readWorkflowMode(contextResult.workspace_root);
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("workflow.get-mode", {
        schema_version: 1,
        effective_mode: mode,
        source: mode === "continuous" ? "default_or_config" : "workspace_config",
        advisory: true
      }, {
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runWorkflowSetMode(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "workflow.set-mode");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const requested = canonicalWorkflowMode(valueAfter(argv, "--mode"));
  if (!requested) {
    return writeError("workflow.set-mode", "workflow_mode_invalid", "Unsupported workflow mode.");
  }
  const previous = readWorkflowMode(contextResult.workspace_root);
  const changed = previous !== requested;
  if (changed) {
    writeWorkflowMode(contextResult.workspace_root, requested);
  }
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("workflow.set-mode", {
        schema_version: 1,
        previous_mode: previous,
        configured_mode: requested,
        effective_mode: requested,
        source: "workspace_config",
        advisory: true,
        changed
      }, {
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runDoctorRoots(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "doctor.roots");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const writable = canWrite(contextResult.data_root);
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("doctor.roots", {
        schema_version: 1,
        workspace_root: contextResult.workspace_root,
        data_root: contextResult.data_root,
        use_cases_root: contextResult.use_cases_root,
        component_id: contextResult.component_id,
        config_path: contextResult.config_path,
        provenance: contextResult.provenance,
        writable
      }, {
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return 0;
}

function runDoctorSkills(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "doctor.skills");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const result = validateSkillAssets({ context: contextResult });
  process.stdout.write(
    `${JSON.stringify(
      createCliResult("doctor.skills", result, {
        ok: result.complete,
        complete: result.complete,
        diagnostics: result.diagnostics,
        workspaceRoot: contextResult.workspace_root,
        dataRoot: contextResult.data_root,
        componentId: contextResult.component_id
      })
    )}\n`
  );
  return result.complete ? 0 : 1;
}

function runDoctorPackage(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "doctor.package");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const tarball = valueAfter(argv, "--tarball");
  const installedRoot = valueAfter(argv, "--installed-root");
  if (tarball && installedRoot) {
    return writeError("doctor.package", "package.target_conflict", "Use only one of --tarball or --installed-root.");
  }
  try {
    const data = inspectPackageArtifact({
      target: tarball
        ? { kind: "tarball", path: resolve(process.cwd(), tarball) }
        : installedRoot
          ? { kind: "installed_root", path: resolve(process.cwd(), installedRoot) }
          : { kind: "workspace", path: contextResult.workspace_root, build: true }
    });
    process.stdout.write(
      `${JSON.stringify(
        createCliResult("doctor.package", data, {
          ok: data.complete,
          complete: data.complete,
          diagnostics: data.diagnostics,
          workspaceRoot: contextResult.workspace_root,
          dataRoot: contextResult.data_root,
          componentId: contextResult.component_id
        })
      )}\n`
    );
    return data.complete ? 0 : 1;
  } catch (error) {
    return writeError("doctor.package", "package.inspection_failed", error instanceof Error ? error.message : String(error));
  }
}

// ---------------------------------------------------------------------------
// Phase 7 use-case-marker commands (bind / scan / prove / validate-ledger).
// Thin wiring: parse argv, resolve paths + injected key material, call the core.
// ---------------------------------------------------------------------------

function markerPaths(argv: string[], context: ResolvedWorkspaceContext) {
  const productRoot = valueAfter(argv, "--product-root")
    ? resolve(process.cwd(), valueAfter(argv, "--product-root") as string)
    : context.workspace_root;
  const bindingsPath = valueAfter(argv, "--bindings")
    ? resolve(process.cwd(), valueAfter(argv, "--bindings") as string)
    : join(context.data_root, ".use-cases", "bindings.jsonl");
  const evidencePath = valueAfter(argv, "--evidence")
    ? resolve(process.cwd(), valueAfter(argv, "--evidence") as string)
    : join(context.data_root, ".use-cases", "evidence.jsonl");
  return { productRoot, bindingsPath, evidencePath };
}

function markerPublicKeyResolver(argv: string[]): ReturnType<typeof singleKeyResolver> {
  // Opt-in multi-key path: --keyring builds a resolver that enforces per-key
  // status (active/revoked) and validity windows against the proof's created_at.
  // When both flags are present the keyring wins over the single --public-key.
  const keyringPath = valueAfter(argv, "--keyring");
  if (keyringPath) {
    return keyringPublicKeyResolverFromFile(resolve(process.cwd(), keyringPath));
  }
  const keyPath = valueAfter(argv, "--public-key");
  if (!keyPath) {
    // No configured key: any proof signature fails (ledger with proofs is invalid).
    return () => undefined;
  }
  const pem = readFileSync(resolve(process.cwd(), keyPath), "utf8");
  return singleKeyResolver(createPublicKey(pem));
}

function markerSigningKey(argv: string[]): { privateKey: ReturnType<typeof createPrivateKey>; keyId: string } | undefined {
  const envName = valueAfter(argv, "--signing-key-env");
  if (!envName) {
    return undefined;
  }
  const pem = process.env[envName];
  if (!pem) {
    return undefined;
  }
  return { privateKey: createPrivateKey(pem), keyId: valueAfter(argv, "--key-id") ?? "trusted-ci" };
}

function runMarkerBind(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "markers.bind");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const rowId = valueAfter(argv, "--row");
  const file = valueAfter(argv, "--file");
  const modeRaw = valueAfter(argv, "--mode");
  if (!rowId || !file || (modeRaw !== "explicit" && modeRaw !== "swift-func")) {
    return writeError("markers.bind", "cli_invalid_arguments", "Missing --row, --file, or --mode (explicit|swift-func).");
  }
  const paths = markerPaths(argv, contextResult);
  const result = runBindCommand({
    context: contextResult,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    rowId,
    suffix: valueAfter(argv, "--suffix"),
    file,
    mode: modeRaw,
    line: numberAfter(argv, "--line"),
    startLine: numberAfter(argv, "--start-line"),
    endLine: numberAfter(argv, "--end-line"),
    commentPrefix: valueAfter(argv, "--comment-prefix"),
    registerExisting: argv.includes("--register-existing"),
    dryRun: argv.includes("--dry-run"),
    clock: () => new Date().toISOString(),
    idFactory: generateUlid,
    version: getVersionInfo().version
  });
  emitMarkerResult("markers.bind", result, contextResult, result.exit_code === 0);
  return result.exit_code;
}

function runMarkerScan(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "markers.scan");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const paths = markerPaths(argv, contextResult);
  const policyModeRaw = valueAfter(argv, "--policy-mode") ?? "feature";
  const policyMode = ["feature", "release", "custom"].includes(policyModeRaw)
    ? (policyModeRaw as "feature" | "release" | "custom")
    : "feature";
  const result = runScanCommand({
    context: contextResult,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    evidencePath: paths.evidencePath,
    policyMode,
    publicKeyResolver: markerPublicKeyResolver(argv),
    generatedAt: valueAfter(argv, "--generated-at") ?? new Date().toISOString(),
    baseRef: valueAfter(argv, "--base-ref"),
    repoCwd: contextResult.workspace_root
  });
  if (argv.includes("--ci") && result.inferred_spans.length > 0) {
    process.stderr.write(`${result.inferred_spans.join("\n\n")}\n`);
  }
  emitMarkerResult("markers.scan", result, contextResult, result.exit_code === 0);
  return result.exit_code;
}

function runMarkerProve(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "markers.prove");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const all = argv.includes("--all");
  const rowId = valueAfter(argv, "--row");
  if (!all && !rowId) {
    return writeError("markers.prove", "cli_invalid_arguments", "Missing --row or --all.");
  }
  const paths = markerPaths(argv, contextResult);

  // prove no longer runs verifiers; it CONSUMES the unsigned verification-results
  // ledger that `verify --out` produced (one JSONL record per row).
  let verificationResults: VerificationResultRecord[] | undefined;
  const resultsPathRaw = valueAfter(argv, "--verification-results");
  if (resultsPathRaw) {
    const resultsPath = resolve(process.cwd(), resultsPathRaw);
    let text: string;
    try {
      text = readFileSync(resultsPath, "utf8");
    } catch {
      return writeError(
        "markers.prove",
        "cli_invalid_arguments",
        `Could not read --verification-results file: ${resultsPath}`
      );
    }
    try {
      verificationResults = text
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((line) => JSON.parse(line) as VerificationResultRecord);
    } catch {
      return writeError(
        "markers.prove",
        "cli_invalid_arguments",
        `--verification-results file is not valid JSONL: ${resultsPath}`
      );
    }
  }

  // DANGEROUS seam (renamed from --verification-result): assume the row's
  // verification passed. The core honours it ONLY when env
  // UCM_ALLOW_UNSAFE_VERIFICATION=1 is set; otherwise it is ignored.
  const unsafeAssume =
    valueAfter(argv, "--unsafe-assume-verification-result") === "pass" ? ("pass" as const) : undefined;

  // CI-neutral provenance authority (additive, signed). An explicit
  // --authority-file (a JSON authority record) wins — for unknown CI / overrides;
  // otherwise auto-detect from the process env. The GitHub-shaped `producer` block
  // below is still populated exactly as before, beside the authority.
  let authority: CiAuthority;
  const authorityFileRaw = valueAfter(argv, "--authority-file");
  if (authorityFileRaw) {
    const authorityPath = resolve(process.cwd(), authorityFileRaw);
    let authorityText: string;
    try {
      authorityText = readFileSync(authorityPath, "utf8");
    } catch {
      return writeError(
        "markers.prove",
        "cli_invalid_arguments",
        `Could not read --authority-file: ${authorityPath}`
      );
    }
    try {
      authority = JSON.parse(authorityText) as CiAuthority;
    } catch {
      return writeError(
        "markers.prove",
        "cli_invalid_arguments",
        `--authority-file is not valid JSON: ${authorityPath}`
      );
    }
  } else {
    authority = detectCiAuthority(process.env);
  }

  const result = runProveCommand({
    context: contextResult,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    evidencePath: paths.evidencePath,
    publicKeyResolver: markerPublicKeyResolver(argv),
    rowId,
    all,
    refresh: argv.includes("--refresh"),
    trustedCi: argv.includes("--trusted-ci"),
    append: argv.includes("--append"),
    dryRun: argv.includes("--dry-run"),
    verificationResults,
    unsafeAssumeVerificationResult: unsafeAssume,
    signingKey: markerSigningKey(argv),
    producer: {
      ci_run_id: process.env.GITHUB_RUN_ID,
      repo: process.env.GITHUB_REPOSITORY,
      commit: process.env.GITHUB_SHA
    },
    authority,
    generatedAt: valueAfter(argv, "--generated-at") ?? new Date().toISOString(),
    idFactory: generateUlid,
    baseRef: valueAfter(argv, "--base-ref"),
    repoCwd: contextResult.workspace_root
  });
  emitMarkerResult("markers.prove", result, contextResult, result.exit_code === 0);
  return result.exit_code;
}

function runMarkerVerify(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "markers.verify");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const all = argv.includes("--all");
  const rowId = valueAfter(argv, "--row");
  if (!all && !rowId) {
    return writeError("markers.verify", "cli_invalid_arguments", "Missing --all or --row <slug>.");
  }
  const paths = markerPaths(argv, contextResult);
  const outRaw = valueAfter(argv, "--out");
  const result = runVerifyCommand({
    context: contextResult,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    evidencePath: paths.evidencePath,
    publicKeyResolver: markerPublicKeyResolver(argv),
    all,
    rowId,
    outPath: outRaw ? resolve(process.cwd(), outRaw) : undefined,
    generatedAt: valueAfter(argv, "--generated-at") ?? new Date().toISOString(),
    baseRef: valueAfter(argv, "--base-ref"),
    repoCwd: contextResult.workspace_root
  });
  emitMarkerResult("markers.verify", result, contextResult, result.exit_code === 0);
  return result.exit_code;
}

function runMarkerValidateLedger(argv: string[]): number {
  const contextResult = contextFromArgs(argv, "markers.validate-ledger");
  if ("exitCode" in contextResult) {
    return contextResult.exitCode;
  }
  const paths = markerPaths(argv, contextResult);
  const result = runValidateLedgerCommand({
    context: contextResult,
    evidencePath: paths.evidencePath,
    bindingsPath: paths.bindingsPath,
    publicKeyResolver: markerPublicKeyResolver(argv),
    baseRef: valueAfter(argv, "--base-ref"),
    repoCwd: contextResult.workspace_root
  });
  emitMarkerResult("markers.validate-ledger", result, contextResult, result.ok);
  return result.exit_code;
}

function emitMarkerResult(
  command: string,
  data: { exit_code: number },
  context: ResolvedWorkspaceContext,
  ok: boolean
): void {
  process.stdout.write(
    `${JSON.stringify(
      createCliResult(command, data, {
        ok,
        complete: ok,
        workspaceRoot: context.workspace_root,
        dataRoot: context.data_root,
        componentId: context.component_id
      })
    )}\n`
  );
}

// Minimal ULID-shaped id for registry/proof event ids (uniqueness from the tail).
function generateUlid(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  const time = Date.now().toString(32).toUpperCase().padStart(10, "0").slice(0, 10);
  let tail = "";
  for (let i = 0; i < 16; i += 1) {
    tail += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `${time}${tail}`.slice(0, 26).padEnd(26, "0");
}

function contextFromArgs(argv: string[], command: string) {
  const workspaceRoot = resolve(process.cwd(), valueAfter(argv, "--repo") ?? ".");
  const dataRootValue = valueAfter(argv, "--data-root");
  if (dataRootValue) {
    const dataRoot = resolve(process.cwd(), dataRootValue);
    const rel = relative(workspaceRoot, dataRoot);
    if (rel === ".." || rel.startsWith(`..${"/"}`) || isAbsolute(rel)) {
      return {
        exitCode: writeError(command, "unsafe_data_root", "--data-root must stay inside --repo.", 4)
      };
    }
  }
  return resolveWorkspaceContext({
    workspaceRoot,
    dataRootOverride: dataRootValue ? resolve(process.cwd(), dataRootValue) : undefined,
    component: valueAfter(argv, "--component")
  });
}

function writeError(command: string, code: string, message: string, exitCode = 2): number {
  process.stdout.write(
    `${JSON.stringify(
      createCliResult(
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
      )
    )}\n`
  );
  return exitCode;
}

function readWorkflowMode(workspaceRoot: string): string {
  const configPath = join(workspaceRoot, "presentation-skills.yml");
  const source = readFileSync(configPath, "utf8");
  return source.match(/^default_workflow_mode:\s*([a-z_]+)/m)?.[1] ?? "continuous";
}

function writeWorkflowMode(workspaceRoot: string, mode: string): void {
  const configPath = join(workspaceRoot, "presentation-skills.yml");
  const source = readFileSync(configPath, "utf8");
  const next = source.match(/^default_workflow_mode:/m)
    ? source.replace(/^default_workflow_mode:\s*[a-z_]+/m, `default_workflow_mode: ${mode}`)
    : `${source.trimEnd()}\ndefault_workflow_mode: ${mode}\n`;
  const tempPath = `${configPath}.tmp`;
  writeFileSync(tempPath, next);
  renameSync(tempPath, configPath);
}

function canonicalWorkflowMode(value: string | undefined): string | null {
  if (!value) {
    return null;
  }
  const normalized = value.replaceAll("-", "_");
  return ["continuous", "backfill", "showcase_only", "audit_only", "migration", "custom"].includes(normalized)
    ? normalized
    : null;
}

function canWrite(path: string): boolean {
  try {
    accessSync(path, constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

function valueAfter(argv: string[], flag: string): string | undefined {
  const index = argv.indexOf(flag);
  if (index === -1) {
    return undefined;
  }
  return argv[index + 1];
}

function valuesAfter(argv: string[], flag: string): string[] | undefined {
  const values: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === flag && argv[index + 1]) {
      values.push(argv[index + 1]);
    }
  }
  return values.length > 0 ? values : undefined;
}

function numberAfter(argv: string[], flag: string): number | undefined {
  const value = valueAfter(argv, flag);
  if (!value) {
    return undefined;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function isEntrypoint(): boolean {
  if (!process.argv[1]) {
    return false;
  }

  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntrypoint()) {
  process.exitCode = runCli(process.argv.slice(2));
}
