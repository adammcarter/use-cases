import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { extname, isAbsolute, join, relative, sep } from "node:path";
import type { ResolvedWorkspaceContext } from "../roots.js";
import {
  computeSemanticHash,
  parseYamlToJson,
  validateBySchemaId,
  type Diagnostic,
  type ParsedYamlResult
} from "../schema/index.js";
import { loadUseCaseMatrix } from "../useCases/loadUseCaseMatrix.js";
import { replayEvidence } from "../evidence/index.js";
import { selectShowcasePlan, selectWalkthroughPlan } from "../presentation/index.js";
import type { CapsuleFileResult, CapsulePlanResult, CapsuleSnapshot, DemoCapsule, LoadedDemoCapsule } from "./types.js";

const DEMO_CAPSULE_SCHEMA_ID = "https://use-case-matrix.dev/schemas/v1/demo-capsule.schema.json";

export function demoCapsulesRoot(context: ResolvedWorkspaceContext): string {
  return join(context.data_root, "demo-capsules");
}

export function loadDemoCapsules(options: { context: ResolvedWorkspaceContext }): CapsuleSnapshot {
  const diagnostics: Diagnostic[] = [];
  const files: CapsuleFileResult[] = [];
  const capsules: LoadedDemoCapsule[] = [];
  const root = demoCapsulesRoot(options.context);

  if (!existsSync(root)) {
    return { schema_version: 1, complete: true, files, capsules, diagnostics };
  }

  const seen = new Map<string, string>();
  const rootRealPath = realpathSync(root);
  for (const entry of listCapsuleEntries(root, root, options.context.data_root, rootRealPath, diagnostics, files)) {
    const result = validateCapsuleFile(entry.filePath, entry.sourcePath);
    files.push(result.file);
    diagnostics.push(...result.diagnostics);
    if (!result.capsule) {
      continue;
    }
    const duplicatePath = seen.get(result.capsule.capsule.capsule_id);
    if (duplicatePath) {
      diagnostics.push(
        diagnostic(
          "capsule.duplicate_id",
          `Duplicate capsule id '${result.capsule.capsule.capsule_id}'.`,
          result.capsule.path,
          result.capsule.capsule.capsule_id,
          [duplicatePath]
        )
      );
      files[files.length - 1] = { ...files[files.length - 1], status: "schema_error" };
      continue;
    }
    seen.set(result.capsule.capsule.capsule_id, result.capsule.path);
    capsules.push(result.capsule);
  }

  return {
    schema_version: 1,
    complete: diagnostics.every((item) => item.severity !== "error"),
    files,
    capsules,
    diagnostics
  };
}

export function planDemoCapsule(options: { context: ResolvedWorkspaceContext; capsuleId: string }): CapsulePlanResult {
  const snapshot = loadDemoCapsules({ context: options.context });
  const capsule = snapshot.capsules.find((candidate) => candidate.capsule.capsule_id === options.capsuleId) ?? null;
  if (!snapshot.complete) {
    return {
      schema_version: 1,
      outcome: "integrity_blocked",
      capsule,
      plan_result: null,
      diagnostics: snapshot.diagnostics
    };
  }
  if (!capsule) {
    return {
      schema_version: 1,
      outcome: "capsule_not_found",
      capsule: null,
      plan_result: null,
      diagnostics: [
        diagnostic("capsule.not_found", `Capsule '${options.capsuleId}' was not found.`, null, options.capsuleId)
      ]
    };
  }

  const matrix = loadUseCaseMatrix({ context: options.context });
  const evidence = replayEvidence({ context: options.context });
  const request = {
    audience: capsule.capsule.audience,
    timeboxSeconds: capsule.capsule.timebox_seconds,
    maxItems: capsule.capsule.items.length,
    requestedUseCaseIds: capsule.capsule.items.map((item) => item.use_case_id),
    generatedAt: "2026-06-25T12:00:00.000Z",
    freshnessEvaluatedAt: "2026-06-25T12:00:00.000Z"
  };
  const planResult =
    capsule.capsule.mode === "showcase"
      ? selectShowcasePlan({ context: options.context, matrix, evidence, request })
      : selectWalkthroughPlan({ context: options.context, matrix, evidence, request });

  return {
    schema_version: 1,
    outcome: "generated",
    capsule,
    plan_result: planResult,
    diagnostics: [...snapshot.diagnostics, ...matrix.diagnostics, ...evidence.diagnostics]
  };
}

function validateCapsuleFile(filePath: string, sourcePath: string): {
  file: CapsuleFileResult;
  capsule: LoadedDemoCapsule | null;
  diagnostics: Diagnostic[];
} {
  const source = readFileSync(filePath, "utf8");
  const fileHash = computeSemanticHash(source);
  const parsed = parseCapsuleSource(source, sourcePath, extname(filePath));
  if (!parsed.ok) {
    return {
      file: { path: sourcePath, status: "parse_error", file_hash: fileHash },
      capsule: null,
      diagnostics: parsed.diagnostics
    };
  }
  const validation = validateBySchemaId(DEMO_CAPSULE_SCHEMA_ID, parsed.value, sourcePath);
  if (!validation.ok) {
    return {
      file: { path: sourcePath, status: "schema_error", file_hash: fileHash },
      capsule: null,
      diagnostics: validation.diagnostics
    };
  }
  return {
    file: { path: sourcePath, status: "loaded", file_hash: fileHash },
    capsule: {
      capsule: parsed.value as DemoCapsule,
      path: sourcePath,
      semantic_hash: computeSemanticHash(parsed.value)
    },
    diagnostics: []
  };
}

function parseCapsuleSource(source: string, sourcePath: string, extension: string): ParsedYamlResult {
  if (extension === ".json") {
    try {
      return { ok: true, value: JSON.parse(source) as unknown, diagnostics: [] };
    } catch (error) {
      return {
        ok: false,
        diagnostics: [diagnostic("parse_error", error instanceof Error ? error.message : String(error), sourcePath)]
      };
    }
  }
  return parseYamlToJson(source, sourcePath);
}

function listCapsuleEntries(
  root: string,
  current: string,
  dataRoot: string,
  rootRealPath: string,
  diagnostics: Diagnostic[],
  files: CapsuleFileResult[]
): Array<{ filePath: string; sourcePath: string }> {
  const entries = readdirSync(current, { withFileTypes: true }).sort((left, right) =>
    left.name.localeCompare(right.name)
  );
  const results: Array<{ filePath: string; sourcePath: string }> = [];

  for (const entry of entries) {
    const fullPath = join(current, entry.name);
    const sourcePath = relative(dataRoot, fullPath).split(sep).join("/");
    const stat = lstatSync(fullPath);

    if (stat.isSymbolicLink()) {
      files.push({ path: sourcePath, status: "symlink_rejected" });
      diagnostics.push(diagnostic("capsule.symlink_rejected", "Symlinks under demo-capsules are not followed.", sourcePath));
      continue;
    }
    if (stat.isDirectory()) {
      results.push(...listCapsuleEntries(root, fullPath, dataRoot, rootRealPath, diagnostics, files));
      continue;
    }
    if (!stat.isFile()) {
      files.push({ path: sourcePath, status: "io_error" });
      diagnostics.push(diagnostic("capsule.io_error", "Only regular files are supported under demo-capsules.", sourcePath));
      continue;
    }
    if (![".yml", ".yaml", ".json"].includes(extname(fullPath))) {
      continue;
    }
    const realPath = realpathSync(fullPath);
    const rel = relative(rootRealPath, realPath);
    if (rel.startsWith("..") || isAbsolute(rel)) {
      files.push({ path: sourcePath, status: "path_escape" });
      diagnostics.push(diagnostic("capsule.path_escape", "Capsule file escapes demo-capsules root.", sourcePath));
      continue;
    }
    results.push({ filePath: fullPath, sourcePath });
  }

  return results;
}

function diagnostic(
  code: string,
  message: string,
  sourcePath: string | null,
  entityId: string | null = null,
  relatedIds: string[] = []
): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: entityId,
    related_ids: relatedIds
  };
}
