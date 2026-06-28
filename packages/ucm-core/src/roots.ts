import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { PresentationSkillsError } from "./errors.js";
import {
  parseYamlToJson,
  validateBySchemaId,
  type Diagnostic
} from "./schema/index.js";

export type ResolveWorkspaceContextOptions = {
  workspaceRoot?: string;
  dataRootOverride?: string;
  component?: string;
  pluginRoot?: string;
};

export type ResolvedWorkspaceContext = {
  plugin_root: string;
  workspace_root: string;
  data_root: string;
  use_cases_root: string;
  component_id: string;
  config_path: string | null;
  // The workspace config's verifiers map+default, normalized for the verifier
  // resolver. Threaded identically into verify/prove/scan so a row's resolved
  // verifier (and thus its verification context hash) is computed consistently.
  verifiers: ResolvedWorkspaceVerifiers;
  provenance: {
    workspace_root: "explicit" | "cwd";
    data_root: "override" | "workspace_config" | "default";
    use_cases_root: "workspace_config" | "default";
    component_id: "option" | "workspace_config" | "default";
  };
  diagnostics: Diagnostic[];
};

// An explicit script verifier or a preset reference, mirroring
// common.schema.json#/$defs/verifier. Kept structurally loose here (the schema
// is the source of truth) so additive shape changes don't require lockstep edits.
export type WorkspaceVerifierEntry =
  | {
      kind: "script";
      evidence_kind: string;
      command: string[];
      inputs?: string[];
      timeout_seconds?: number;
    }
  | {
      preset: string;
      evidence_kind?: string;
      inputs?: string[];
      timeout_seconds?: number;
    };

// The optional workspace-config `verifiers` section: a map of verifier-id ->
// entry, plus an optional `default` verifier-id rows can fall back to.
export type WorkspaceVerifiersConfig = {
  default?: string;
} & {
  [verifierId: string]: WorkspaceVerifierEntry | string | undefined;
};

// The normalized verifiers config carried on a ResolvedWorkspaceContext: the
// `default` id split out from the entry map. Structurally compatible with the
// resolver's WorkspaceVerifierContext, so it threads straight through.
export type ResolvedWorkspaceVerifiers = {
  default?: string;
  verifiers: Record<string, WorkspaceVerifierEntry>;
};

type WorkspaceConfig = {
  data_root?: string;
  use_cases_dir?: string;
  component_id?: string;
  verifiers?: WorkspaceVerifiersConfig;
};

export function resolveWorkspaceContext(
  options: ResolveWorkspaceContextOptions = {}
): ResolvedWorkspaceContext {
  const workspaceRootInput = options.workspaceRoot ?? process.cwd();
  const workspaceRoot = realpathIfExists(resolve(workspaceRootInput));
  const pluginRoot = realpathIfExists(
    options.pluginRoot ?? resolve(dirname(fileURLToPath(import.meta.url)), "../../..")
  );
  const configPath = join(workspaceRoot, "presentation-skills.yml");
  const config = existsSync(configPath) ? readWorkspaceConfig(configPath, workspaceRoot) : null;

  if (options.component && config?.value.component_id && options.component !== config.value.component_id) {
    throw new PresentationSkillsError(
      `Unknown component '${options.component}'. Declared component is '${config.value.component_id}'.`,
      "component.unknown"
    );
  }

  const dataRootValue = options.dataRootOverride ?? config?.value.data_root ?? ".";
  const dataRoot = realpathIfExists(resolveRelative(workspaceRoot, dataRootValue));
  const useCasesDir = config?.value.use_cases_dir ?? "use-cases";
  const useCasesRoot = resolveRelative(dataRoot, useCasesDir);
  ensureContained(dataRoot, useCasesRoot, "use_cases_dir escapes data_root");

  return {
    plugin_root: pluginRoot,
    workspace_root: workspaceRoot,
    data_root: dataRoot,
    use_cases_root: useCasesRoot,
    component_id: options.component ?? config?.value.component_id ?? "presentation-skills",
    config_path: existsSync(configPath) ? "presentation-skills.yml" : null,
    verifiers: normalizeWorkspaceVerifiers(config?.value.verifiers),
    provenance: {
      workspace_root: options.workspaceRoot ? "explicit" : "cwd",
      data_root: options.dataRootOverride ? "override" : config?.value.data_root ? "workspace_config" : "default",
      use_cases_root: config?.value.use_cases_dir ? "workspace_config" : "default",
      component_id: options.component ? "option" : config?.value.component_id ? "workspace_config" : "default"
    },
    diagnostics: config?.diagnostics ?? []
  };
}

function readWorkspaceConfig(
  configPath: string,
  workspaceRoot: string
): { value: WorkspaceConfig; diagnostics: Diagnostic[] } {
  const source = readFileSync(configPath, "utf8");
  const parsed = parseYamlToJson(source, "presentation-skills.yml");
  if (!parsed.ok) {
    throw new PresentationSkillsError("Unable to parse presentation-skills.yml.", "workspace_config.parse_error");
  }
  const validation = validateBySchemaId(
    "https://use-case-matrix.dev/schemas/v1/workspace-config.schema.json",
    parsed.value,
    "presentation-skills.yml"
  );
  if (!validation.ok) {
    throw new PresentationSkillsError("Invalid presentation-skills.yml.", "workspace_config.schema_error");
  }
  if (!isRecord(parsed.value)) {
    throw new PresentationSkillsError("Invalid presentation-skills.yml.", "workspace_config.schema_error");
  }

  const config = parsed.value as WorkspaceConfig;
  for (const value of [config.data_root, config.use_cases_dir]) {
    if (value) {
      ensureRelativeSafe(value);
    }
  }

  return {
    value: config,
    diagnostics: validation.diagnostics.map((diagnostic) => ({
      ...diagnostic,
      source_path: relative(workspaceRoot, configPath).split(sep).join("/")
    }))
  };
}

// Split the raw `verifiers` config into { default, verifiers } — the shape the
// verifier resolver consumes. The schema guarantees entries are objects and
// `default` is a string, but we re-check defensively (config may be hand-edited).
function normalizeWorkspaceVerifiers(
  raw: WorkspaceVerifiersConfig | undefined
): ResolvedWorkspaceVerifiers {
  if (!isRecord(raw)) {
    return { verifiers: {} };
  }
  const verifiers: Record<string, WorkspaceVerifierEntry> = {};
  for (const [id, entry] of Object.entries(raw)) {
    if (id === "default") {
      continue;
    }
    if (isRecord(entry)) {
      verifiers[id] = entry as WorkspaceVerifierEntry;
    }
  }
  return typeof raw.default === "string"
    ? { default: raw.default, verifiers }
    : { verifiers };
}

function resolveRelative(root: string, value: string): string {
  return isAbsolute(value) ? resolve(value) : resolve(root, value);
}

function realpathIfExists(path: string): string {
  return existsSync(path) ? realpathSync(path) : path;
}

function ensureRelativeSafe(value: string): void {
  if (isAbsolute(value) || value.split(/[\\/]/).includes("..")) {
    throw new PresentationSkillsError(`Unsafe relative path '${value}'.`, "path.escape");
  }
}

function ensureContained(root: string, child: string, message: string): void {
  const relativePath = relative(root, child);
  if (relativePath === "" || (!relativePath.startsWith("..") && !isAbsolute(relativePath))) {
    return;
  }
  throw new PresentationSkillsError(message, "path.escape");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
