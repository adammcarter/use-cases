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
  provenance: {
    workspace_root: "explicit" | "cwd";
    data_root: "override" | "workspace_config" | "default";
    use_cases_root: "workspace_config" | "default";
    component_id: "option" | "workspace_config" | "default";
  };
  diagnostics: Diagnostic[];
};

type WorkspaceConfig = {
  data_root?: string;
  use_cases_dir?: string;
  component_id?: string;
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
