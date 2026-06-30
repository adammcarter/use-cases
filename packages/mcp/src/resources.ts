// MCP resources: READ-ONLY views of Use Cases Plugin workspace state (MCP 2025-11-25).
//
// Each resource reuses the same read-only cores the CLI/tools wrap and returns
// the SAME structured JSON. Resources NEVER mutate, run verifiers, or mint
// proofs. A repo-scoped resource resolves its workspace from a `?repo=` query
// segment on the URI, or the server's configured default
// (UCP_MCP_REPO). The repo is bound, symlink-safe, to an allowed
// root (the configured default, else the server cwd); a traversal path is
// rejected before any disk read. Schema resources need no repo.
import { join, resolve } from "node:path";
import type { ResolvedWorkspaceContext } from "@use-cases-plugin/core";

type UcmCoreModule = typeof import("@use-cases-plugin/core");

const {
  PresentationSkillsError,
  createCliResult,
  getPublicSchemas,
  loadUseCaseMatrix,
  prepareScan,
  queryUseCases,
  replayEvidence,
  resolveContainedPath,
  resolveWorkspaceContext,
  runScanCommand,
  runValidateLedgerCommand,
  toEvidenceStatusResult,
  toMatrixListResult,
  toMatrixValidationResult
} = await loadUcmCore();

async function loadUcmCore(): Promise<UcmCoreModule> {
  try {
    return await import("@use-cases-plugin/core");
  } catch (error) {
    if (!isMissingCorePackage(error)) {
      throw error;
    }
    const bundledCoreSpecifier = "../../core/dist/index.js";
    return await import(bundledCoreSpecifier) as UcmCoreModule;
  }
}

function isMissingCorePackage(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ERR_MODULE_NOT_FOUND" && error.message.includes("@use-cases-plugin/core");
}

const JSON_MIME = "application/json";

// JSON-RPC error codes (MCP 2025-11-25): -32602 invalid params, -32002 resource
// not found. Used so the index handler can map a failed read to a JSON-RPC error.
const INVALID_PARAMS = -32602;
const RESOURCE_NOT_FOUND = -32002;

export type McpResourceDescriptor = {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
};

export const mcpResources: McpResourceDescriptor[] = [
  {
    uri: "ucp://matrix",
    name: "Use-case matrix",
    description: "Matrix validation result plus the full list of use cases (read-only). Add ?repo=<path> or configure UCP_MCP_REPO.",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://matrix/status",
    name: "Matrix + evidence status",
    description: "Combined matrix validation and evidence assurance status (read-only).",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://freshness",
    name: "Marker freshness status",
    description: "Read-only freshness scan (marker bindings vs proofs) — the same status `ucp scan` emits. Never runs verifiers.",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://bindings",
    name: "Marker binding registry",
    description: "The materialized append-only binding registry (row id -> binding slugs), read-only.",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://ledger",
    name: "Proof ledger validation",
    description: "Read-only validate-ledger summary: evidence/registry integrity, append-only discipline, and hash-chain status.",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://evidence",
    name: "Evidence assurance status",
    description: "Replayed evidence assurance status for the matrix (read-only).",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://schemas",
    name: "Public schema index",
    description: "Index of public Use Cases Plugin JSON schemas. Read an individual schema at ucp://schemas/{name} (e.g. ucp://schemas/common.schema.json). No repo required.",
    mimeType: JSON_MIME
  },
  {
    uri: "ucp://config",
    name: "Resolved workspace config",
    description: "Resolved workspace roots and config provenance for a repo (read-only).",
    mimeType: JSON_MIME
  }
];

export type ReadResourceOutcome =
  | { ok: true; contents: Array<{ uri: string; mimeType: string; text: string }> }
  | { ok: false; code: number; message: string };

export function listMcpResources(): McpResourceDescriptor[] {
  return mcpResources;
}

export function readMcpResource(uri: string): ReadResourceOutcome {
  const parsed = parseUcmUri(uri);
  if (!parsed) {
    return { ok: false, code: RESOURCE_NOT_FOUND, message: `Unknown resource: ${uri}` };
  }

  // Schema resources need no repo.
  if (parsed.key === "schemas") {
    return contents(uri, schemasIndex());
  }
  if (parsed.key.startsWith("schemas/")) {
    const name = parsed.key.slice("schemas/".length);
    const found = findSchema(name);
    if (!found) {
      return { ok: false, code: RESOURCE_NOT_FOUND, message: `Unknown schema: ${name}` };
    }
    return contents(uri, { id: found.id, schema: found.schema });
  }

  // Every other resource is repo-scoped.
  const resolved = resolveResourceContext(parsed.repo);
  if ("error" in resolved) {
    return resolved.error;
  }
  const context = resolved.context;

  switch (parsed.key) {
    case "matrix":
      return contents(uri, matrixView(context));
    case "matrix/status":
      return contents(uri, matrixStatusView(context));
    case "freshness":
      return contents(uri, freshnessView(context));
    case "bindings":
      return contents(uri, bindingsView(context));
    case "ledger":
      return contents(uri, ledgerView(context));
    case "evidence":
      return contents(uri, evidenceView(context));
    case "config":
      return contents(uri, configView(context));
    default:
      return { ok: false, code: RESOURCE_NOT_FOUND, message: `Unknown resource: ${uri}` };
  }
}

type ParsedUri = { key: string; repo: string | null };

function parseUcmUri(uri: string): ParsedUri | null {
  let url: URL;
  try {
    url = new URL(uri);
  } catch {
    return null;
  }
  if (url.protocol !== "ucp:") {
    return null;
  }
  const host = url.hostname;
  const path = url.pathname.replace(/^\/+/, "").replace(/\/+$/, "");
  const key = path ? `${host}/${path}` : host;
  return { key, repo: url.searchParams.get("repo") };
}

function resolveResourceContext(
  repoFromUri: string | null
): { context: ResolvedWorkspaceContext } | { error: ReadResourceOutcome } {
  const repoValue = repoFromUri ?? defaultRepo();
  if (!repoValue) {
    return {
      error: {
        ok: false,
        code: INVALID_PARAMS,
        message: "This resource requires a repo: add ?repo=<path> to the URI or set UCP_MCP_REPO."
      }
    };
  }
  let workspaceRoot: string;
  try {
    workspaceRoot = resolveContainedPath(allowedRepoRoot(), repoValue, "repo escapes the allowed workspace root boundary.");
  } catch (error) {
    if (error instanceof PresentationSkillsError && error.code === "path.escape") {
      return { error: { ok: false, code: INVALID_PARAMS, message: `UCP_PATH_ESCAPE: ${error.message}` } };
    }
    throw error;
  }
  return { context: resolveWorkspaceContext({ workspaceRoot }) };
}

function allowedRepoRoot(): string {
  const configured = process.env.UCP_MCP_REPO;
  return configured && configured.length > 0 ? resolve(configured) : process.cwd();
}

function defaultRepo(): string | null {
  const configured = process.env.UCP_MCP_REPO;
  return configured && configured.length > 0 ? configured : null;
}

function markerPaths(context: ResolvedWorkspaceContext) {
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "evidence.jsonl")
  };
}

// No proof-signing key is configured for read-only views, mirroring the CLI
// default (`ucp scan` / `ucp validate-ledger` without --public-key).
function noKeyResolver(): undefined {
  return undefined;
}

function matrixView(context: ResolvedWorkspaceContext) {
  const snapshot = loadUseCaseMatrix({ context });
  const all = queryUseCases(snapshot, {});
  return createCliResult(
    "matrix.validate",
    {
      schema_version: 1,
      validation: toMatrixValidationResult(snapshot),
      list: toMatrixListResult(snapshot, all)
    },
    {
      ok: true,
      complete: snapshot.complete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }
  );
}

function matrixStatusView(context: ResolvedWorkspaceContext) {
  const matrix = loadUseCaseMatrix({ context });
  const evidence = replayEvidence({ context });
  const complete = matrix.complete && evidence.complete;
  return createCliResult(
    "matrix.status",
    {
      schema_version: 1,
      complete,
      matrix: toMatrixValidationResult(matrix),
      evidence: toEvidenceStatusResult(evidence)
    },
    {
      ok: complete,
      complete,
      diagnostics: [...matrix.diagnostics, ...evidence.diagnostics],
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }
  );
}

function freshnessView(context: ResolvedWorkspaceContext) {
  const paths = markerPaths(context);
  const result = runScanCommand({
    context,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    evidencePath: paths.evidencePath,
    policyMode: "feature",
    publicKeyResolver: noKeyResolver,
    generatedAt: new Date().toISOString(),
    repoCwd: context.workspace_root
  });
  return createCliResult("markers.scan", result, {
    ok: result.exit_code === 0,
    complete: result.exit_code === 0,
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
}

function bindingsView(context: ResolvedWorkspaceContext) {
  const paths = markerPaths(context);
  const prepared = prepareScan({
    context,
    productRoot: paths.productRoot,
    bindingsPath: paths.bindingsPath,
    evidencePath: paths.evidencePath,
    policyMode: "feature",
    publicKeyResolver: noKeyResolver,
    generatedAt: new Date().toISOString(),
    repoCwd: context.workspace_root
  });
  const rows = [...prepared.registry.rowToSlugs.entries()]
    .map(([row_id, slugs]) => ({ row_id, binding_slugs: [...slugs].sort() }))
    .sort((a, b) => a.row_id.localeCompare(b.row_id));
  const slugs = [...prepared.registry.slugToRow.entries()]
    .map(([slug, row_id]) => ({ slug, row_id }))
    .sort((a, b) => a.slug.localeCompare(b.slug));
  const registryValid = prepared.registryErrors.length === 0;
  return createCliResult(
    "markers.bindings",
    {
      schema_version: 1,
      registry_valid: registryValid,
      rows,
      slugs,
      registry_errors: prepared.registryErrors
    },
    {
      ok: registryValid,
      complete: registryValid,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }
  );
}

function ledgerView(context: ResolvedWorkspaceContext) {
  const paths = markerPaths(context);
  const result = runValidateLedgerCommand({
    context,
    evidencePath: paths.evidencePath,
    bindingsPath: paths.bindingsPath,
    publicKeyResolver: noKeyResolver,
    repoCwd: context.workspace_root
  });
  return createCliResult("markers.validate-ledger", result, {
    ok: result.ok,
    complete: result.ok,
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
}

function evidenceView(context: ResolvedWorkspaceContext) {
  const snapshot = replayEvidence({ context });
  return createCliResult("evidence.status", toEvidenceStatusResult(snapshot), {
    ok: snapshot.complete,
    complete: snapshot.complete,
    diagnostics: snapshot.diagnostics,
    workspaceRoot: context.workspace_root,
    dataRoot: context.data_root,
    componentId: context.component_id
  });
}

function configView(context: ResolvedWorkspaceContext) {
  return createCliResult(
    "doctor.roots",
    {
      schema_version: 1,
      workspace_root: context.workspace_root,
      data_root: context.data_root,
      use_cases_root: context.use_cases_root,
      component_id: context.component_id,
      config_path: context.config_path,
      provenance: context.provenance
    },
    {
      ok: true,
      complete: true,
      diagnostics: context.diagnostics,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }
  );
}

function schemasIndex() {
  return {
    schema_version: 1,
    schemas: getPublicSchemas().map(({ id }) => ({
      id,
      name: id.split("/").pop() ?? id,
      uri: `ucp://schemas/${id.split("/").pop() ?? id}`
    }))
  };
}

function findSchema(name: string): { id: string; schema: unknown } | undefined {
  return getPublicSchemas().find(({ id }) => {
    const base = id.split("/").pop() ?? id;
    const short = base.replace(/\.schema\.json$/, "");
    return id === name || base === name || short === name;
  });
}

function contents(uri: string, payload: unknown): ReadResourceOutcome {
  return {
    ok: true,
    contents: [{ uri, mimeType: JSON_MIME, text: JSON.stringify(payload) }]
  };
}
