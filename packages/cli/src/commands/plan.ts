import type { CliCommand, CommandOutput } from "../command/types.js";
import { numberAfter, valueAfter, valuesAfter } from "../args/parse.js";
import {
  containedPathOrError,
  createCliResult,
  errorEnvelope,
  loadPresentationPlanFile,
  loadUseCaseMatrix,
  renderCard,
  replayEvidence,
  resolveContextOrError,
  selectShowcasePlan,
  selectWalkthroughPlan
} from "../runtime.js";
import { repoFlag, dataRootFlag, componentFlag, jsonFlag, workspaceFlags } from "./common.js";

// Shared port of the legacy `runPlan(argv, mode)` — builds the same request, calls
// the same selector, and surfaces matrix+evidence diagnostics in the envelope
// regardless of outcome. Returns envelope + exit code instead of writing stdout.
function planOutput(argv: string[], mode: "showcase" | "walkthrough"): CommandOutput {
  const context = resolveContextOrError(argv, `plan.${mode}`);
  if (context.kind === "error") {
    return { envelope: context.envelope, exitCode: context.exitCode };
  }
  const ctx = context.context;
  const matrix = loadUseCaseMatrix({ context: ctx });
  const evidence = replayEvidence({ context: ctx });
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
      ? selectShowcasePlan({ context: ctx, matrix, evidence, request })
      : selectWalkthroughPlan({ context: ctx, matrix, evidence, request });
  const ok = result.outcome !== "integrity_blocked";
  const complete = result.plan?.complete ?? (result.outcome === "no_eligible_items" && matrix.complete && evidence.complete);
  const envelope = createCliResult(`plan.${mode}`, result, {
    ok,
    complete,
    diagnostics: [...matrix.diagnostics, ...evidence.diagnostics],
    workspaceRoot: ctx.workspace_root,
    dataRoot: ctx.data_root,
    componentId: ctx.component_id
  });
  if (result.outcome === "integrity_blocked") {
    return { envelope, exitCode: 3 };
  }
  if (result.outcome === "no_eligible_items") {
    return { envelope, exitCode: 1 };
  }
  return { envelope, exitCode: 0 };
}

const planRequestFlags = [
  { key: "audience", name: "--audience", kind: "string", valueName: "<role>", summary: "Audience role for the plan (default reviewer)." },
  { key: "timebox", name: "--timebox", kind: "integer", valueName: "<seconds>", summary: "Timebox budget in seconds." },
  { key: "maxItems", name: "--max-items", kind: "integer", valueName: "<n>", summary: "Cap the number of selected items." },
  { key: "host", name: "--host", kind: "string", valueName: "<surface>", summary: "Host surface to plan for (default unknown)." },
  { key: "changedPath", name: "--changed-path", kind: "string", repeatable: true, valueName: "<path>", summary: "Bias selection toward changed paths (repeatable)." },
  { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." },
  { key: "strict", name: "--strict", kind: "boolean", summary: "Fail when the matrix/evidence is incomplete." }
] as const;

export const planShowcaseCommand: CliCommand = {
  path: ["plan", "showcase"],
  command: "plan.showcase",
  summary: "Select a showcase presentation plan.",
  flags: [...workspaceFlags, ...planRequestFlags],
  handler: ({ argv }) => planOutput(argv, "showcase")
};

export const planWalkthroughCommand: CliCommand = {
  path: ["plan", "walkthrough"],
  command: "plan.walkthrough",
  summary: "Select a walkthrough presentation plan.",
  flags: [...workspaceFlags, ...planRequestFlags],
  handler: ({ argv }) => planOutput(argv, "walkthrough")
};

export const planCardsCommand: CliCommand = {
  path: ["plan", "cards"],
  command: "plan.cards",
  summary: "Render presentation cards from a saved plan file.",
  flags: [
    repoFlag,
    dataRootFlag,
    componentFlag,
    { key: "planFile", name: "--plan-file", kind: "string", required: true, valueName: "<path>", summary: "Saved presentation plan file (inside the workspace)." },
    jsonFlag
  ],
  handler: ({ argv }) => {
    const context = resolveContextOrError(argv, "plan.cards");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const planFile = valueAfter(argv, "--plan-file");
    if (!planFile) {
      return {
        envelope: errorEnvelope("plan.cards", "cli_invalid_arguments", "Missing --plan-file."),
        exitCode: 2
      };
    }
    const contained = containedPathOrError("plan.cards", ctx.workspace_root, planFile);
    if (contained.kind === "error") {
      return { envelope: contained.envelope, exitCode: contained.exitCode };
    }
    const planPath = contained.path;
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
      return {
        envelope: createCliResult("plan.cards", data, {
          ok: true,
          complete: true,
          workspaceRoot: ctx.workspace_root,
          dataRoot: ctx.data_root,
          componentId: ctx.component_id
        }),
        exitCode: 0
      };
    } catch (error) {
      const code = error instanceof Error && "code" in error ? String(error.code) : "internal_error";
      return {
        envelope: errorEnvelope("plan.cards", code, error instanceof Error ? error.message : String(error)),
        exitCode: 1
      };
    }
  }
};

export const planCommands: CliCommand[] = [planShowcaseCommand, planWalkthroughCommand, planCardsCommand];
