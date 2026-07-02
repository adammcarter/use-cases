import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, extname, join, relative, sep } from "node:path";
import { parseDocument } from "yaml";
import { diagnostic, isRecord, type Diagnostic } from "./diagnostic.js";
import { PUBLIC_SCHEMA_IDS, schemaIdForName, validateBySchemaId } from "./registry.js";
import { validateSyntheticCommonContracts } from "./syntheticContracts.js";

export type ParsedYamlResult =
  | { ok: true; value: unknown; diagnostics: Diagnostic[] }
  | { ok: false; value?: undefined; diagnostics: Diagnostic[] };

export type FixtureValidationResult = {
  ok: boolean;
  complete: boolean;
  diagnostics: Diagnostic[];
  validated_schema_ids: string[];
  expected_state?: unknown;
};

export function parseYamlToJson(source: string, sourcePath: string): ParsedYamlResult {
  if (/^\s*<<\s*:/m.test(source)) {
    return {
      ok: false,
      diagnostics: [diagnostic("yaml.merge_key_rejected", "YAML merge keys are not supported.", sourcePath)]
    };
  }
  if (/(^|[\s,[{])![A-Za-z]/.test(source)) {
    return {
      ok: false,
      diagnostics: [diagnostic("yaml.custom_tag_rejected", "Custom YAML tags are not supported.", sourcePath)]
    };
  }

  const document = parseDocument(source, {
    merge: false,
    prettyErrors: false,
    schema: "core",
    uniqueKeys: true
  });
  const yamlProblems = [...document.errors, ...document.warnings];
  if (yamlProblems.length > 0) {
    return {
      ok: false,
      diagnostics: yamlProblems.map((problem) =>
        diagnostic(
          problem.code === "DUPLICATE_KEY" ? "yaml.duplicate_key" : "parse_error",
          problem.message,
          sourcePath
        )
      )
    };
  }

  return {
    ok: true,
    value: document.toJSON(),
    diagnostics: []
  };
}

export function computeSemanticHash(value: unknown): string {
  return `sha256:${createHash("sha256").update(canonicalJson(value)).digest("hex")}`;
}

export function validateFixtureWorkspace(workspacePath: string): FixtureValidationResult {
  const diagnostics: Diagnostic[] = [];
  const validated = new Set<string>();
  const useCaseIds = new Map<string, string>();
  const expectedPath = join(workspacePath, "expected.json");
  const expected = existsSync(expectedPath)
    ? (JSON.parse(readFileSync(expectedPath, "utf8")) as { expected_state?: unknown })
    : {};

  validateSyntheticCommonContracts(validated, diagnostics);

  for (const filePath of listFiles(workspacePath)) {
    const relPath = relative(workspacePath, filePath).split(sep).join("/");
    if (relPath === "expected.json") {
      continue;
    }

    const schemaId = schemaIdForFixturePath(relPath);
    const extension = extname(filePath);
    if (!schemaId && extension !== ".yml" && extension !== ".yaml") {
      continue;
    }

    if (extension === ".jsonl") {
      validateJsonLines(filePath, relPath, schemaId, validated, diagnostics);
      continue;
    }

    const parsed = parseFixtureFile(filePath, relPath);
    diagnostics.push(...parsed.diagnostics);
    if (!parsed.ok) {
      continue;
    }

    if (schemaId) {
      const result = validateBySchemaId(schemaId, parsed.value, relPath);
      validated.add(schemaId);
      diagnostics.push(...result.diagnostics);
    }

    if (schemaId === schemaIdForName("use-case-file.schema.json")) {
      collectUseCaseIds(parsed.value, relPath, useCaseIds, diagnostics);
    }
  }

  const complete = !diagnostics.some((item) => item.severity === "error");
  return {
    ok: complete,
    complete,
    diagnostics,
    validated_schema_ids: PUBLIC_SCHEMA_IDS.filter((id) => validated.has(id)),
    expected_state: expected.expected_state
  };
}

function validateJsonLines(
  filePath: string,
  relPath: string,
  schemaId: string | undefined,
  validated: Set<string>,
  diagnostics: Diagnostic[]
) {
  if (!schemaId) {
    return;
  }
  const lines = readFileSync(filePath, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  for (const [index, line] of lines.entries()) {
    try {
      const value = JSON.parse(line) as unknown;
      const result = validateBySchemaId(schemaId, value, `${relPath}:${index + 1}`);
      validated.add(schemaId);
      diagnostics.push(...result.diagnostics);
    } catch (error) {
      diagnostics.push(
        diagnostic(
          "parse_error",
          error instanceof Error ? error.message : String(error),
          `${relPath}:${index + 1}`
        )
      );
    }
  }
}

function parseFixtureFile(filePath: string, relPath: string): ParsedYamlResult {
  const extension = extname(filePath);
  const source = readFileSync(filePath, "utf8");
  if (extension === ".json") {
    try {
      return { ok: true, value: JSON.parse(source) as unknown, diagnostics: [] };
    } catch (error) {
      return {
        ok: false,
        diagnostics: [
          diagnostic("parse_error", error instanceof Error ? error.message : String(error), relPath)
        ]
      };
    }
  }

  return parseYamlToJson(source, relPath);
}

function collectUseCaseIds(
  value: unknown,
  relPath: string,
  seen: Map<string, string>,
  diagnostics: Diagnostic[]
) {
  if (!isRecord(value) || !Array.isArray(value.use_cases)) {
    return;
  }
  for (const useCase of value.use_cases) {
    if (!isRecord(useCase) || typeof useCase.id !== "string") {
      continue;
    }
    const previousPath = seen.get(useCase.id);
    if (previousPath) {
      diagnostics.push({
        ...diagnostic(
          "workspace.duplicate_use_case_id",
          `Use case '${useCase.id}' appears in both ${previousPath} and ${relPath}.`,
          relPath
        ),
        entity_id: useCase.id,
        related_ids: [previousPath]
      });
    } else {
      seen.set(useCase.id, relPath);
    }
  }
}

function schemaIdForFixturePath(relPath: string): string | undefined {
  if (relPath === "use-case-matrix.yml") {
    return schemaIdForName("workspace-config.schema.json");
  }
  if (relPath.startsWith("workflow-modes/") || basename(relPath) === "valid-sibling.yml") {
    return schemaIdForName("workflow-mode.schema.json");
  }
  if (relPath.startsWith("use-cases/")) {
    return schemaIdForName("use-case-file.schema.json");
  }
  if (relPath.startsWith("evidence/")) {
    return schemaIdForName("evidence-event.schema.json");
  }
  if (relPath.startsWith("demo-capsules/")) {
    return schemaIdForName("demo-capsule.schema.json");
  }
  if (relPath.startsWith("presentation-plans/")) {
    return schemaIdForName("presentation-plan.schema.json");
  }
  if (relPath.startsWith("showcase-runs/")) {
    return schemaIdForName("showcase-event.schema.json");
  }
  if (relPath.startsWith("hosts/")) {
    return schemaIdForName("host-profile.schema.json");
  }
  if (relPath.startsWith("host-status/")) {
    return schemaIdForName("host-status-result.schema.json");
  }
  if (relPath.startsWith("migrations/")) {
    return schemaIdForName("migration-test-matrix-result.schema.json");
  }
  return undefined;
}

function listFiles(root: string): string[] {
  if (!existsSync(root)) {
    return [];
  }
  const entries = readdirSync(root, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const fullPath = join(root, entry.name);
    if (entry.isDirectory()) {
      files.push(...listFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }
  return files.sort();
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, item]) => item !== undefined)
    .sort(([left], [right]) => left.localeCompare(right));
  return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${canonicalJson(item)}`).join(",")}}`;
}
