import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, extname, isAbsolute, join, relative, sep } from "node:path";
import { parseDocument, stringify } from "yaml";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { computeSemanticHash, diagnostic, validateBySchemaId, type Diagnostic } from "../schema/index.js";
import { loadUseCaseMatrix } from "./loadUseCaseMatrix.js";
import type { UseCaseV1 } from "./types.js";

const USE_CASE_FILE_SCHEMA_ID = "https://use-cases.dev/schemas/v1/use-case-file.schema.json";
const RECORDED_AT = "1970-01-01T00:00:00.000Z";

export type UseCaseMutationOperation = "upsert" | "remove";

export type UseCaseMutationOptions = {
  context: ResolvedWorkspaceContext;
  operation: UseCaseMutationOperation;
  targetFile?: string;
  useCaseId?: string;
  useCase?: Record<string, unknown>;
  expectedSemanticHash?: string;
  reason?: string;
  actor?: "agent" | "user" | "script" | "system";
};

export type UseCaseMutationResult = {
  schema_version: 1;
  operation: UseCaseMutationOperation;
  status: "created" | "updated" | "removed" | "blocked";
  use_case_id: string | null;
  file_path: string | null;
  before_hash: string | null;
  after_hash: string | null;
  diagnostics: Diagnostic[];
};

type UseCaseFileDocument = {
  schema_version: 1;
  feature: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  use_cases: UseCaseV1[];
  extensions?: Record<string, unknown>;
};

export function mutateUseCaseMatrix(options: UseCaseMutationOptions): UseCaseMutationResult {
  const matrix = loadUseCaseMatrix({ context: options.context });
  if (!matrix.complete) {
    return blocked(options, "matrix.mutation_incomplete_matrix", "Use cases must be complete before mutation.");
  }

  if (options.operation === "upsert") {
    return upsertUseCase(options);
  }
  return removeUseCase(options);
}

function upsertUseCase(options: UseCaseMutationOptions): UseCaseMutationResult {
  if (!options.targetFile || !options.useCase) {
    return blocked(options, "matrix.mutation_invalid_arguments", "Missing targetFile or useCase.");
  }
  const id = typeof options.useCase.id === "string" ? options.useCase.id : null;
  if (!id) {
    return blocked(options, "matrix.mutation_missing_use_case_id", "Use case JSON must include an id.");
  }

  const target = resolveTargetFile(options.context, options.targetFile);
  if ("diagnostic" in target) {
    return blocked(options, target.diagnostic.code, target.diagnostic.message, id);
  }
  const parsed = readUseCaseFile(target.fullPath, target.sourcePath);
  if ("diagnostic" in parsed) {
    return blocked(options, parsed.diagnostic.code, parsed.diagnostic.message, id, target.sourcePath);
  }

  const existingIndex = parsed.document.use_cases.findIndex((item) => item.id === id);
  const existing = existingIndex >= 0 ? parsed.document.use_cases[existingIndex] : null;
  const beforeHash = existing ? computeSemanticHash(existing) : null;
  if (existing && options.expectedSemanticHash && options.expectedSemanticHash !== beforeHash) {
    return blocked(options, "matrix.mutation_hash_mismatch", "Existing use-case hash did not match expected hash.", id, target.sourcePath, beforeHash);
  }

  const nextUseCase = options.useCase as UseCaseV1;
  if (existingIndex >= 0) {
    parsed.document.use_cases[existingIndex] = nextUseCase;
  } else {
    parsed.document.use_cases.push(nextUseCase);
  }
  const validation = validateBySchemaId(USE_CASE_FILE_SCHEMA_ID, parsed.document, target.sourcePath);
  if (!validation.ok) {
    return {
      schema_version: 1,
      operation: "upsert",
      status: "blocked",
      use_case_id: id,
      file_path: target.sourcePath,
      before_hash: beforeHash,
      after_hash: null,
      diagnostics: validation.diagnostics
    };
  }

  writeUseCaseFile(target.fullPath, parsed.document);
  return {
    schema_version: 1,
    operation: "upsert",
    status: existing ? "updated" : "created",
    use_case_id: id,
    file_path: target.sourcePath,
    before_hash: beforeHash,
    after_hash: computeSemanticHash(nextUseCase),
    diagnostics: []
  };
}

function removeUseCase(options: UseCaseMutationOptions): UseCaseMutationResult {
  if (!options.useCaseId || !options.reason) {
    return blocked(options, "matrix.mutation_invalid_arguments", "Missing useCaseId or reason.");
  }
  const matrix = loadUseCaseMatrix({ context: options.context });
  const resolved = matrix.resolveUseCase(options.useCaseId);
  if (resolved.kind !== "resolved") {
    return blocked(options, "matrix.mutation_unresolved_use_case", `Use case '${options.useCaseId}' is ${resolved.kind}.`, options.useCaseId);
  }

  const sourcePath = resolved.useCase.source.path;
  const fullPath = join(options.context.data_root, sourcePath.split("/").join(sep));
  const parsed = readUseCaseFile(fullPath, sourcePath);
  if ("diagnostic" in parsed) {
    return blocked(options, parsed.diagnostic.code, parsed.diagnostic.message, options.useCaseId, sourcePath);
  }

  const existingIndex = parsed.document.use_cases.findIndex((item) => item.id === options.useCaseId);
  if (existingIndex < 0) {
    return blocked(options, "matrix.mutation_unresolved_use_case", `Use case '${options.useCaseId}' was not found in its source file.`, options.useCaseId, sourcePath);
  }

  const existing = parsed.document.use_cases[existingIndex];
  const beforeHash = computeSemanticHash(existing);
  if (options.expectedSemanticHash && options.expectedSemanticHash !== beforeHash) {
    return blocked(options, "matrix.mutation_hash_mismatch", "Existing use-case hash did not match expected hash.", options.useCaseId, sourcePath, beforeHash);
  }

  const next = {
    ...existing,
    lifecycle: "removed" as const,
    extensions: {
      ...asRecord(existing.extensions),
      "use-cases/removal": {
        ...asRecord(asRecord(existing.extensions)["use-cases/removal"]),
        reason: options.reason,
        actor: options.actor ?? "agent",
        recorded_at: RECORDED_AT
      }
    }
  };
  parsed.document.use_cases[existingIndex] = next;
  const validation = validateBySchemaId(USE_CASE_FILE_SCHEMA_ID, parsed.document, sourcePath);
  if (!validation.ok) {
    return {
      schema_version: 1,
      operation: "remove",
      status: "blocked",
      use_case_id: options.useCaseId,
      file_path: sourcePath,
      before_hash: beforeHash,
      after_hash: null,
      diagnostics: validation.diagnostics
    };
  }

  writeUseCaseFile(fullPath, parsed.document);
  return {
    schema_version: 1,
    operation: "remove",
    status: "removed",
    use_case_id: options.useCaseId,
    file_path: sourcePath,
    before_hash: beforeHash,
    after_hash: computeSemanticHash(next),
    diagnostics: []
  };
}

function resolveTargetFile(context: ResolvedWorkspaceContext, requestedPath: string):
  | { fullPath: string; sourcePath: string }
  | { diagnostic: Diagnostic } {
  const normalized = requestedPath.replaceAll("\\", "/");
  if (isAbsolute(normalized) || normalized.split("/").includes("..")) {
    return { diagnostic: diagnostic("matrix.mutation_path_escape", "Target file must stay under use-cases.", requestedPath) };
  }
  if (![".yml", ".yaml"].includes(extname(normalized))) {
    return { diagnostic: diagnostic("matrix.mutation_invalid_file", "Target file must be .yml or .yaml.", requestedPath) };
  }
  const stripped = normalized.startsWith("use-cases/") ? normalized.slice("use-cases/".length) : normalized;
  const fullPath = join(context.use_cases_root, stripped);
  const rel = relative(context.use_cases_root, fullPath);
  if (rel === "" || rel.startsWith("..") || isAbsolute(rel)) {
    return { diagnostic: diagnostic("matrix.mutation_path_escape", "Target file must stay under use-cases.", requestedPath) };
  }
  return {
    fullPath,
    sourcePath: relative(context.data_root, fullPath).split(sep).join("/")
  };
}

function readUseCaseFile(fullPath: string, sourcePath: string):
  | { document: UseCaseFileDocument }
  | { diagnostic: Diagnostic } {
  if (!existsSync(fullPath)) {
    return { diagnostic: diagnostic("matrix.mutation_file_missing", "Target use-case file does not exist.", sourcePath) };
  }
  const source = readFileSync(fullPath, "utf8");
  const parsed = parseDocument(source, {
    merge: false,
    prettyErrors: false,
    schema: "core",
    uniqueKeys: true
  });
  const problems = [...parsed.errors, ...parsed.warnings];
  if (problems.length > 0) {
    return {
      diagnostic: diagnostic("matrix.mutation_parse_error", problems[0]?.message ?? "Could not parse target YAML.", sourcePath)
    };
  }
  const value = parsed.toJSON() as UseCaseFileDocument;
  if (!value || !Array.isArray(value.use_cases)) {
    return { diagnostic: diagnostic("matrix.mutation_invalid_file", "Target file is not a use-case file.", sourcePath) };
  }
  return { document: value };
}

function writeUseCaseFile(fullPath: string, document: UseCaseFileDocument): void {
  mkdirSync(dirname(fullPath), { recursive: true });
  const tempPath = `${fullPath}.tmp-${process.pid}`;
  writeFileSync(tempPath, stringify(document, { lineWidth: 0 }));
  renameSync(tempPath, fullPath);
}

function blocked(
  options: UseCaseMutationOptions,
  code: string,
  message: string,
  useCaseId: string | null = options.useCaseId ?? null,
  filePath: string | null = null,
  beforeHash: string | null = null
): UseCaseMutationResult {
  return {
    schema_version: 1,
    operation: options.operation,
    status: "blocked",
    use_case_id: useCaseId,
    file_path: filePath,
    before_hash: beforeHash,
    after_hash: null,
    diagnostics: [diagnostic(code, message, filePath, useCaseId)]
  };
}


function asRecord(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {};
}
