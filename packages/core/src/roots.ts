import { existsSync, readFileSync, realpathSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { UseCasesPluginError } from "./errors.js";
import {
  diagnostic,
  parseYamlToJson,
  validateBySchemaId,
  type Diagnostic
} from "./schema/index.js";
import { DEFAULT_COMPONENT_ID } from "./version.js";

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
  // OPTIONAL CI-neutral release-gate authority requirement (off by default).
  // Threaded into deriveFreshness so a required_for_release row whose matching
  // FRESH proof was minted with insufficient provenance authority is policy-
  // blocked in RELEASE mode. Undefined => no requirement (behaviour unchanged).
  release_gate?: WorkspaceReleaseGate;
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

// The optional workspace-config `release_gate` section (mirrors
// workspace-config.schema.json#/$defs/release_gate). Structurally compatible
// with freshness.ts `ReleaseGatePolicy`, so it threads straight through.
export type WorkspaceReleaseGate = {
  required_authority?: "ci";
  require_protected_ref?: boolean;
};

type WorkspaceConfig = {
  data_root?: string;
  use_cases_dir?: string;
  component_id?: string;
  verifiers?: WorkspaceVerifiersConfig;
  release_gate?: WorkspaceReleaseGate;
};

export function resolveWorkspaceContext(
  options: ResolveWorkspaceContextOptions = {}
): ResolvedWorkspaceContext {
  const workspaceRootInput = options.workspaceRoot ?? process.cwd();
  const workspaceRoot = realpathIfExists(resolve(workspaceRootInput));
  const pluginRoot = realpathIfExists(
    options.pluginRoot ?? resolve(dirname(fileURLToPath(import.meta.url)), "../../..")
  );
  const configPath = join(workspaceRoot, "use-cases.yml");
  const config = existsSync(configPath) ? readWorkspaceConfig(configPath, workspaceRoot) : null;

  if (options.component && config?.value.component_id && options.component !== config.value.component_id) {
    throw new UseCasesPluginError(
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
    component_id: options.component ?? config?.value.component_id ?? DEFAULT_COMPONENT_ID,
    config_path: existsSync(configPath) ? "use-cases.yml" : null,
    verifiers: normalizeWorkspaceVerifiers(config?.value.verifiers),
    release_gate: normalizeReleaseGate(config?.value.release_gate),
    provenance: {
      workspace_root: options.workspaceRoot ? "explicit" : "cwd",
      data_root: options.dataRootOverride ? "override" : config?.value.data_root ? "workspace_config" : "default",
      use_cases_root: config?.value.use_cases_dir ? "workspace_config" : "default",
      component_id: options.component ? "option" : config?.value.component_id ? "workspace_config" : "default"
    },
    diagnostics: config?.diagnostics ?? []
  };
}

// Canonical diagnostic code for a workspace root that does not exist on disk.
// Single source of truth so the CLI and MCP transports emit an identical code.
export const WORKSPACE_NOT_FOUND_CODE = "workspace.not_found";

// Shared READ-side workspace-existence guard. A non-existent workspace root is a
// user typo (a mistyped or stale --repo/repo), NOT a valid empty workspace: without
// this guard the read-only matrix inspection surface (matrix validate/list/status)
// reports a missing path as a clean, valid, zero-use-case matrix — a silent wrong
// answer. Both transports' context resolvers call this (the CLI's
// `resolveContextOrError` and the MCP's `contextFromArgs`) so a bad repo yields the
// SAME `workspace.not_found` envelope on both — upholding the "envelopes match on
// both transports" contract, and giving any future workspace tool the guard for
// free. Returns the canonical diagnostic when the root is missing, else null.
//
// An existing-but-empty directory is still legitimate (the "not populated" case).
// Deliberately NOT wired into the write/scaffold path (`uc init`), which
// legitimately targets a not-yet-existing root and has its own existence handling.
// `workspaceRoot` MUST already be resolved to an absolute path by the caller.
export function workspaceNotFoundDiagnostic(workspaceRoot: string): Diagnostic | null {
  return existsSync(workspaceRoot)
    ? null
    : diagnostic(WORKSPACE_NOT_FOUND_CODE, `repo path does not exist: ${workspaceRoot}`);
}

function readWorkspaceConfig(
  configPath: string,
  workspaceRoot: string
): { value: WorkspaceConfig; diagnostics: Diagnostic[] } {
  const source = readFileSync(configPath, "utf8");
  const parsed = parseYamlToJson(source, "use-cases.yml");
  if (!parsed.ok) {
    throw new UseCasesPluginError("Unable to parse use-cases.yml.", "workspace_config.parse_error");
  }
  const validation = validateBySchemaId(
    "https://use-cases.dev/schemas/v1/workspace-config.schema.json",
    parsed.value,
    "use-cases.yml"
  );
  if (!validation.ok) {
    throw new UseCasesPluginError("Invalid use-cases.yml.", "workspace_config.schema_error");
  }
  if (!isRecord(parsed.value)) {
    throw new UseCasesPluginError("Invalid use-cases.yml.", "workspace_config.schema_error");
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

// Normalize the optional `release_gate` config into a clean policy, or undefined
// when nothing meaningful is set. The schema already validates shape; we re-read
// defensively (config may be hand-edited) and drop an empty/all-falsy object so
// downstream sees `undefined` (== no requirement, behaviour unchanged).
function normalizeReleaseGate(
  raw: WorkspaceReleaseGate | undefined
): WorkspaceReleaseGate | undefined {
  if (!isRecord(raw)) {
    return undefined;
  }
  const gate: WorkspaceReleaseGate = {};
  if (raw.required_authority === "ci") {
    gate.required_authority = "ci";
  }
  if (raw.require_protected_ref === true) {
    gate.require_protected_ref = true;
  }
  return gate.required_authority !== undefined || gate.require_protected_ref !== undefined
    ? gate
    : undefined;
}

function resolveRelative(root: string, value: string): string {
  return isAbsolute(value) ? resolve(value) : resolve(root, value);
}

function realpathIfExists(path: string): string {
  return existsSync(path) ? realpathSync(path) : path;
}

function ensureRelativeSafe(value: string): void {
  if (isAbsolute(value) || value.split(/[\\/]/).includes("..")) {
    throw new UseCasesPluginError(`Unsafe relative path '${value}'.`, "path.escape");
  }
}

// The canonical id pattern, mirroring schemas/v1/common.schema.json $defs.id.
// SECURITY: this is the single guard that keeps a user-supplied id (showcase run
// id, plan item id, evidence id, ...) from becoming a path-traversal segment.
// Because it forbids '/', '\\', '..', leading separators, and absolute paths, an
// id that passes this check is always a single safe path segment. The drift test
// in test/roots/idValidation.test.ts asserts this source equals the schema's.
export const CANONICAL_ID_PATTERN = /^[a-z0-9][a-z0-9_-]*(?:\.[a-z0-9][a-z0-9_-]*)*$/;

/** True when `value` is a string matching the canonical id pattern. */
export function isValidId(value: unknown): value is string {
  return typeof value === "string" && CANONICAL_ID_PATTERN.test(value);
}

/**
 * Throw a stable `path.invalid_id` error (mapped to public `UCM_INVALID_ID`)
 * when `value` is not a canonical id. Use this at every boundary where a
 * user-supplied id becomes a filesystem path segment or a ledger lookup key,
 * BEFORE the id is joined into a path, so traversal can never reach the disk.
 */
export function assertValidId(value: unknown, paramName: string): asserts value is string {
  if (!isValidId(value)) {
    throw new UseCasesPluginError(
      `Invalid ${paramName} '${String(value)}': must be a canonical id (lowercase, no path separators, no '..').`,
      "path.invalid_id"
    );
  }
}

function ensureContained(root: string, child: string, message: string): void {
  const relativePath = relative(root, child);
  if (relativePath === "" || (!relativePath.startsWith("..") && !isAbsolute(relativePath))) {
    return;
  }
  throw new UseCasesPluginError(message, "path.escape");
}

// Resolve the deepest existing ancestor of `target` to its realpath, then recombine
// the not-yet-existing suffix. This lets a containment check see THROUGH a symlinked
// parent directory (or a symlinked leaf) without requiring the leaf itself to exist,
// so a write target whose parent escapes via a symlink is still caught. A realpath
// failure (e.g. EACCES on an intermediate dir) returns the input unchanged; callers
// compare against a realpath'd root, so an unresolved escape still fails containment.
function realpathOfExistingPrefix(target: string): string {
  try {
    if (existsSync(target)) {
      return realpathSync(target);
    }
  } catch {
    return target;
  }
  const parent = dirname(target);
  if (parent === target) {
    return target;
  }
  return join(realpathOfExistingPrefix(parent), basename(target));
}

/**
 * True when `target` stays inside `root` after resolving symlinks. Both sides are
 * realpath-resolved (root, and the existing prefix of target) so the check is
 * symlink-safe AND immune to symlinked-tmpdir aliasing (e.g. macOS /var -> /private/var):
 * a lexical-only compare would wrongly reject an in-workspace absolute path whose root
 * was realpath'd to a different prefix. Resolving the target only stats the path — it
 * never reads file contents — so an escaping path is rejected before it can be opened.
 */
export function isPathContained(root: string, target: string): boolean {
  const realRoot = realpathOfExistingPrefix(resolve(root));
  const realTarget = realpathOfExistingPrefix(resolve(target));
  const realRelative = relative(realRoot, realTarget);
  return realRelative === "" || (!realRelative.startsWith("..") && !isAbsolute(realRelative));
}

/**
 * SECURITY: bound a user-supplied file path to `root`, symlink-safe. Returns the
 * resolved absolute path, or throws a stable `path.escape` (public UCM_PATH_ESCAPE)
 * UseCasesPluginError when the path — after resolving symlinks on its existing
 * prefix — escapes `root`. Use at every boundary where an attacker-
 * controlled path (`--plan-file`, a host projection target, ...) becomes a
 * filesystem read or write, BEFORE the path is opened.
 */
export function resolveContainedPath(
  root: string,
  candidate: string,
  message = "Path escapes the workspace boundary."
): string {
  const resolved = isAbsolute(candidate) ? resolve(candidate) : resolve(root, candidate);
  if (!isPathContained(root, resolved)) {
    throw new UseCasesPluginError(message, "path.escape");
  }
  return resolved;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
