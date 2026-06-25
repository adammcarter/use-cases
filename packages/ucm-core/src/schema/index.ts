import Ajv2020Module, { type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, cpSync } from "node:fs";
import { basename, extname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { parseDocument } from "yaml";

export type Diagnostic = {
  code: string;
  severity: "info" | "warning" | "error";
  message: string;
  source_path: string | null;
  json_pointer: string | null;
  source_span?: {
    start: { line: number; column: number };
    end: { line: number; column: number };
  };
  entity_id: string | null;
  related_ids: string[];
};

export type ValidationResult = {
  ok: boolean;
  diagnostics: Diagnostic[];
};

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

export type CliContext = {
  workspace_root: string;
  data_root: string;
  component_id: string;
  workspace_snapshot: {
    repository_id: string;
    vcs: "git" | "none" | "unknown";
    head_revision: string;
    dirty: boolean;
    working_tree_digest: string;
    component_id: string;
    captured_at: string;
  };
};

export type CliResult<T> = {
  schema_version: 1;
  protocol_version: 1;
  command: string;
  ok: boolean;
  complete: boolean;
  data: T;
  diagnostics: Diagnostic[];
  context: CliContext;
};

export const PUBLIC_SCHEMA_IDS = [
  "https://presentation-skills.dev/schemas/v1/common.schema.json",
  "https://presentation-skills.dev/schemas/v1/cli-result.schema.json",
  "https://presentation-skills.dev/schemas/v1/use-case-file.schema.json",
  "https://presentation-skills.dev/schemas/v1/evidence-event.schema.json",
  "https://presentation-skills.dev/schemas/v1/demo-capsule.schema.json",
  "https://presentation-skills.dev/schemas/v1/presentation-plan.schema.json",
  "https://presentation-skills.dev/schemas/v1/showcase-event.schema.json",
  "https://presentation-skills.dev/schemas/v1/host-profile.schema.json",
  "https://presentation-skills.dev/schemas/v1/host-status-result.schema.json",
  "https://presentation-skills.dev/schemas/v1/workspace-config.schema.json",
  "https://presentation-skills.dev/schemas/v1/workflow-mode.schema.json",
  "https://presentation-skills.dev/schemas/v1/matrix-validation-result.schema.json",
  "https://presentation-skills.dev/schemas/v1/matrix-list-result.schema.json"
] as const;

const SCHEMA_FILE_NAMES = [
  "common.schema.json",
  "cli-result.schema.json",
  "use-case-file.schema.json",
  "evidence-event.schema.json",
  "demo-capsule.schema.json",
  "presentation-plan.schema.json",
  "showcase-event.schema.json",
  "host-profile.schema.json",
  "host-status-result.schema.json",
  "workspace-config.schema.json",
  "workflow-mode.schema.json",
  "matrix-validation-result.schema.json",
  "matrix-list-result.schema.json"
] as const;

let schemaCache: Map<string, unknown> | undefined;
let validatorCache: Map<string, ValidateFunction> | undefined;

export function getPublicSchemas(): Array<{ id: string; schema: unknown }> {
  const schemas = loadSchemas();
  return PUBLIC_SCHEMA_IDS.map((id) => ({ id, schema: schemas.get(id) }));
}

export function validatePublicSchemas(): { ok: boolean; schema_count: number; diagnostics: Diagnostic[] } {
  try {
    buildValidators();
    return {
      ok: true,
      schema_count: PUBLIC_SCHEMA_IDS.length,
      diagnostics: []
    };
  } catch (error) {
    return {
      ok: false,
      schema_count: 0,
      diagnostics: [
        diagnostic(
          "schema.compile_failed",
          error instanceof Error ? error.message : String(error),
          null
        )
      ]
    };
  }
}

export function validateBySchemaId(schemaId: string, value: unknown, sourcePath: string | null = null): ValidationResult {
  const validator = buildValidators().get(schemaId);
  if (!validator) {
    return {
      ok: false,
      diagnostics: [diagnostic("schema.unknown", `Unknown schema: ${schemaId}`, sourcePath)]
    };
  }

  const ok = validator(value);
  return {
    ok,
    diagnostics: ok ? [] : mapAjvErrors(validator.errors ?? [], sourcePath)
  };
}

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

export function createCliResult<T>(
  command: string,
  data: T,
  options: {
    ok?: boolean;
    complete?: boolean;
    diagnostics?: Diagnostic[];
    workspaceRoot?: string;
    dataRoot?: string;
    componentId?: string;
  } = {}
): CliResult<T> {
  const workspaceRoot = options.workspaceRoot ?? process.cwd();
  const dataRoot = options.dataRoot ?? workspaceRoot;
  const componentId = options.componentId ?? "presentation-skills";
  return {
    schema_version: 1,
    protocol_version: 1,
    command,
    ok: options.ok ?? true,
    complete: options.complete ?? true,
    data,
    diagnostics: options.diagnostics ?? [],
    context: {
      workspace_root: workspaceRoot,
      data_root: dataRoot,
      component_id: componentId,
      workspace_snapshot: {
        repository_id: "unknown",
        vcs: "unknown",
        head_revision: "unknown",
        dirty: false,
        working_tree_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        component_id: componentId,
        captured_at: new Date(0).toISOString()
      }
    }
  };
}

export function copySchemasToDist(): void {
  const source = findSchemasDir();
  const destination = fileURLToPath(new URL("../../dist/schemas/v1/", import.meta.url));
  rmSync(destination, { recursive: true, force: true });
  mkdirSync(destination, { recursive: true });
  for (const fileName of SCHEMA_FILE_NAMES) {
    cpSync(join(source, fileName), join(destination, fileName));
  }
}

function validateSyntheticCommonContracts(validated: Set<string>, diagnostics: Diagnostic[]) {
  const common = validateBySchemaId(schemaIdForName("common.schema.json"), {
    schema_version: 1
  });
  validated.add(schemaIdForName("common.schema.json"));
  diagnostics.push(...common.diagnostics);

  const cli = validateBySchemaId(
    schemaIdForName("cli-result.schema.json"),
    createCliResult("schema.synthetic", {})
  );
  validated.add(schemaIdForName("cli-result.schema.json"));
  diagnostics.push(...cli.diagnostics);

  const matrixValidation = validateBySchemaId(schemaIdForName("matrix-validation-result.schema.json"), {
    schema_version: 1,
    complete: true,
    integrity: {
      state: "clean",
      populated: false,
      blocking_diagnostic_count: 0
    },
    files: [],
    counts: {
      files_discovered: 0,
      files_loaded: 0,
      files_excluded: 0,
      use_case_candidates: 0,
      use_cases_addressable: 0,
      use_cases_ambiguous: 0,
      use_cases_structurally_clean: 0,
      broken_references: 0
    },
    ambiguous_ids: []
  });
  validated.add(schemaIdForName("matrix-validation-result.schema.json"));
  diagnostics.push(...matrixValidation.diagnostics);

  const matrixList = validateBySchemaId(schemaIdForName("matrix-list-result.schema.json"), {
    schema_version: 1,
    complete: true,
    integrity: {
      state: "clean",
      populated: false,
      blocking_diagnostic_count: 0
    },
    use_cases: [],
    counts: {
      returned: 0,
      total_addressable: 0
    }
  });
  validated.add(schemaIdForName("matrix-list-result.schema.json"));
  diagnostics.push(...matrixList.diagnostics);
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
  if (relPath === "presentation-skills.yml") {
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
  return undefined;
}

function buildValidators(): Map<string, ValidateFunction> {
  if (validatorCache) {
    return validatorCache;
  }

  const Ajv2020 = Ajv2020Module.default;
  const ajv = new Ajv2020({
    allErrors: true,
    strict: true
  });
  const schemas = loadSchemas();
  for (const schema of schemas.values()) {
    ajv.addSchema(schema as Record<string, unknown>);
  }

  validatorCache = new Map(
    PUBLIC_SCHEMA_IDS.map((id) => {
      const validator = ajv.getSchema(id);
      if (!validator) {
        throw new Error(`schema did not compile: ${id}`);
      }
      return [id, validator];
    })
  );
  return validatorCache;
}

function loadSchemas(): Map<string, unknown> {
  if (schemaCache) {
    return schemaCache;
  }
  const schemasDir = findSchemasDir();
  schemaCache = new Map(
    SCHEMA_FILE_NAMES.map((fileName) => {
      const schema = JSON.parse(readFileSync(join(schemasDir, fileName), "utf8")) as {
        $id: string;
      };
      return [schema.$id, schema];
    })
  );
  return schemaCache;
}

function findSchemasDir(): string {
  const candidates = [
    fileURLToPath(new URL("../../../../schemas/v1/", import.meta.url)),
    fileURLToPath(new URL("../schemas/v1/", import.meta.url))
  ];
  const found = candidates.find((candidate) => existsSync(join(candidate, "common.schema.json")));
  if (!found) {
    throw new Error(`unable to locate schemas/v1 from ${import.meta.url}`);
  }
  return found;
}

function schemaIdForName(fileName: string): string {
  return `https://presentation-skills.dev/schemas/v1/${fileName}`;
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

function mapAjvErrors(errors: ErrorObject[], sourcePath: string | null): Diagnostic[] {
  return errors.map((error) => {
    const missingProperty =
      error.keyword === "required" && isRecord(error.params)
        ? String(error.params.missingProperty)
        : null;
    return diagnostic(
      diagnosticCode(error, missingProperty),
      error.message ?? "Schema validation failed.",
      sourcePath,
      error.instancePath || null
    );
  });
}

function diagnosticCode(error: ErrorObject, missingProperty: string | null): string {
  if (error.keyword === "additionalProperties") {
    return "additional_property";
  }
  if (error.keyword === "enum" || error.keyword === "const") {
    return "enum.invalid_value";
  }
  if (missingProperty === "schema_version") {
    return "schema_version.required";
  }
  if (missingProperty === "observable_outcomes") {
    return "use_case.observable_outcomes.required";
  }
  if (missingProperty === "approval_policy") {
    return "approval_policy.required";
  }
  if (missingProperty) {
    return `${missingProperty}.required`;
  }
  return `schema.${error.keyword}`;
}

function diagnostic(
  code: string,
  message: string,
  sourcePath: string | null,
  jsonPointer: string | null = null
): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: jsonPointer,
    entity_id: null,
    related_ids: []
  };
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
