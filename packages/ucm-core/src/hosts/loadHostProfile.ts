import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseYamlToJson, validateBySchemaId, type Diagnostic } from "../schema/index.js";
import type { HostName, HostProfile, HostProfileLoadResult } from "./types.js";

const HOST_PROFILE_SCHEMA_ID = "https://presentation-skills.dev/schemas/v1/host-profile.schema.json";

export function loadHostProfile(options: { pluginRoot: string; host: HostName }): HostProfileLoadResult {
  const sourcePath = `hosts/${options.host}.yml`;
  const fullPath = resolveHostProfilePath(options.pluginRoot, options.host);
  if (!existsSync(fullPath)) {
    return {
      schema_version: 1,
      complete: false,
      profile: null,
      diagnostics: [diagnostic("host.profile_missing", `Missing host profile for '${options.host}'.`, sourcePath)]
    };
  }

  const source = readFileSync(fullPath, "utf8");
  const parsed = parseYamlToJson(source, sourcePath);
  if (!parsed.ok) {
    return { schema_version: 1, complete: false, profile: null, diagnostics: parsed.diagnostics };
  }
  const validation = validateBySchemaId(HOST_PROFILE_SCHEMA_ID, parsed.value, sourcePath);
  if (!validation.ok) {
    return { schema_version: 1, complete: false, profile: null, diagnostics: validation.diagnostics };
  }
  return {
    schema_version: 1,
    complete: true,
    profile: parsed.value as HostProfile,
    diagnostics: []
  };
}

function resolveHostProfilePath(pluginRoot: string, host: HostName): string {
  const sourcePath = `hosts/${host}.yml`;
  const repoPath = join(pluginRoot, sourcePath);
  if (existsSync(repoPath)) {
    return repoPath;
  }
  return join(dirname(fileURLToPath(import.meta.url)), "../host-profiles", `${host}.yml`);
}

function diagnostic(code: string, message: string, sourcePath: string): Diagnostic {
  return {
    code,
    severity: "error",
    message,
    source_path: sourcePath,
    json_pointer: null,
    entity_id: null,
    related_ids: []
  };
}
