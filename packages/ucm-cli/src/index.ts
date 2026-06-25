#!/usr/bin/env node
import { accessSync, constants, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  PUBLIC_SCHEMA_IDS,
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  createCliResult,
  getVersionInfo,
  loadUseCaseMatrix,
  queryUseCases,
  replayEvidence,
  resolveWorkspaceContext,
  selectShowcasePlan,
  selectWalkthroughPlan,
  toEvidenceAppendResult,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult,
  validateFixtureWorkspace,
  type UseCaseQuery
} from "@presentation-skills/ucm-core";

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

  if (normalizedArgv[0] === "plan" && normalizedArgv[1] === "showcase" && wantsJson) {
    return runPlan(normalizedArgv, "showcase");
  }

  if (normalizedArgv[0] === "plan" && normalizedArgv[1] === "walkthrough" && wantsJson) {
    return runPlan(normalizedArgv, "walkthrough");
  }

  if (normalizedArgv[0] === "evidence" && normalizedArgv[1] === "record" && wantsJson) {
    return runEvidenceRecord(normalizedArgv);
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

  if (normalizedArgv[0] === "doctor" && normalizedArgv[1] === "roots" && wantsJson) {
    return runDoctorRoots(normalizedArgv);
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
