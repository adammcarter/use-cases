// Resolve the concrete verifier(s) a marker row's verification_policy demands.
//
// A verification_policy in "requirements" mode lists `required_verifiers` ids per
// requirement. Each id resolves CONFIG-DRIVEN, in this order:
//   1. the row's own `verification_policy.verifiers[id]`;
//   2. the WORKSPACE CONFIG's `verifiers[id]`;
//   3. if `id` is the default-convention id ("acceptance") and the workspace
//      config declares `verifiers.default`, the entry that default names;
//   4. otherwise BLOCKED — returned (never thrown) so callers can surface an
//      actionable diagnostic instead of crashing.
//
// A verifier ENTRY (in either map) is either an explicit `{ kind:"script",
// command, ... }` or a preset reference `{ preset, ... }` that resolves via
// `expandPreset` (PIECE 1). There is NO hardcoded pnpm/vitest default any more —
// that convention now lives ONLY in the `js.vitest` preset.
//
// Pure + deterministic: given a row + workspace verifiers the result is sorted by
// verifier_id and deduped, and `{slug}` is substituted everywhere it appears in
// command/inputs.

import { expandPreset } from "./verifierPresets.js";

// The convention id rows reference when they want "the workspace default verifier".
// It carries no built-in command — it resolves ONLY via the workspace config's
// `verifiers.default`. Absent that, it is BLOCKED.
export const DEFAULT_CONVENTION_VERIFIER_ID = "acceptance";

const SLUG_TOKEN = "{slug}";

// The default evidence_kind for an entry that does not declare one (preset refs
// may omit it). Matches the historical default-convention evidence kind.
const DEFAULT_EVIDENCE_KIND = "test_result";

// The minimal row shape this resolver needs: a slug (the row/use-case id, used to
// substitute {slug}) plus the raw verification_policy object.
export interface VerifierResolverRow {
  slug: string;
  verification_policy: unknown;
}

// The workspace-config verifiers map threaded in by the caller. `verifiers` maps
// verifier-id -> entry (explicit script OR preset reference); `default` names the
// entry the default-convention id falls back to. The caller MUST source this from
// the already-resolved workspace context so verify/prove/scan agree byte-for-byte.
export interface WorkspaceVerifierContext {
  default?: string;
  verifiers?: Record<string, unknown>;
}

export interface ResolvedVerifier {
  verifier_id: string;
  status: "resolved";
  source: "policy" | "workspace_config" | "workspace_default";
  kind: "script";
  evidence_kind: string;
  command: string[];
  inputs: string[];
  timeout_seconds?: number;
}

export interface BlockedVerifier {
  verifier_id: string;
  status: "blocked";
  reason: string;
}

export type VerifierResolution = ResolvedVerifier | BlockedVerifier;

// Resolve every required_verifier id referenced by the row's verification_policy.
// The returned array is deduped by verifier_id and sorted ascending for stability.
export function resolveRowVerifiers(
  row: VerifierResolverRow,
  workspace: WorkspaceVerifierContext = {}
): VerifierResolution[] {
  const ids = collectRequiredVerifierIds(row.verification_policy);
  const rowVerifiers = extractVerifiers(row.verification_policy);
  const workspaceVerifiers = isRecord(workspace.verifiers) ? workspace.verifiers : {};
  return ids
    .map((id) => resolveOne(id, row.slug, rowVerifiers, workspaceVerifiers, workspace.default))
    .sort((left, right) =>
      left.verifier_id < right.verifier_id ? -1 : left.verifier_id > right.verifier_id ? 1 : 0
    );
}

function resolveOne(
  id: string,
  slug: string,
  rowVerifiers: Record<string, unknown>,
  workspaceVerifiers: Record<string, unknown>,
  workspaceDefault: string | undefined
): VerifierResolution {
  // 1. The row's own declared verifier.
  if (isRecord(rowVerifiers[id])) {
    return resolveEntry(id, slug, rowVerifiers[id] as Record<string, unknown>, "policy");
  }
  // 2. The workspace config's verifier of the same id.
  if (isRecord(workspaceVerifiers[id])) {
    return resolveEntry(id, slug, workspaceVerifiers[id] as Record<string, unknown>, "workspace_config");
  }
  // 3. The default-convention id, backed by the workspace's `verifiers.default`.
  if (id === DEFAULT_CONVENTION_VERIFIER_ID && typeof workspaceDefault === "string") {
    const target = workspaceVerifiers[workspaceDefault];
    if (isRecord(target)) {
      return resolveEntry(id, slug, target as Record<string, unknown>, "workspace_default");
    }
    return {
      verifier_id: id,
      status: "blocked",
      reason: `workspace verifiers.default '${workspaceDefault}' does not name a declared verifier`
    };
  }
  // 4. Unresolvable: actionable, never thrown.
  return {
    verifier_id: id,
    status: "blocked",
    reason:
      `no verifier '${id}' configured; declare it in the row's verification_policy.verifiers ` +
      `or the workspace verifiers map, or set verifiers.default`
  };
}

// Resolve one verifier ENTRY (explicit script or preset reference) to a concrete
// ResolvedVerifier, substituting {slug}. A preset reference expands via PIECE 1's
// expandPreset; an unknown preset id surfaces as BLOCKED.
function resolveEntry(
  id: string,
  slug: string,
  entry: Record<string, unknown>,
  source: ResolvedVerifier["source"]
): VerifierResolution {
  if (typeof entry.preset === "string") {
    return resolvePresetEntry(id, slug, entry, source);
  }
  return resolveScriptEntry(id, slug, entry, source);
}

function resolvePresetEntry(
  id: string,
  slug: string,
  entry: Record<string, unknown>,
  source: ResolvedVerifier["source"]
): VerifierResolution {
  const expansion = expandPreset(entry.preset as string, slug);
  if (expansion.status === "blocked") {
    return { verifier_id: id, status: "blocked", reason: expansion.reason };
  }
  // The entry may override inputs and supply evidence_kind / timeout_seconds.
  const inputs = Array.isArray(entry.inputs)
    ? toStringArray(entry.inputs).map((part) => substituteSlug(part, slug))
    : expansion.expansion.inputs;
  const resolved: ResolvedVerifier = {
    verifier_id: id,
    status: "resolved",
    source,
    kind: "script",
    evidence_kind:
      typeof entry.evidence_kind === "string" ? entry.evidence_kind : DEFAULT_EVIDENCE_KIND,
    command: expansion.expansion.command,
    inputs
  };
  if (typeof entry.timeout_seconds === "number") {
    resolved.timeout_seconds = entry.timeout_seconds;
  }
  return resolved;
}

function resolveScriptEntry(
  id: string,
  slug: string,
  entry: Record<string, unknown>,
  source: ResolvedVerifier["source"]
): ResolvedVerifier {
  const resolved: ResolvedVerifier = {
    verifier_id: id,
    status: "resolved",
    source,
    kind: "script",
    evidence_kind:
      typeof entry.evidence_kind === "string" ? entry.evidence_kind : DEFAULT_EVIDENCE_KIND,
    command: toStringArray(entry.command).map((part) => substituteSlug(part, slug)),
    inputs: toStringArray(entry.inputs).map((part) => substituteSlug(part, slug))
  };
  if (typeof entry.timeout_seconds === "number") {
    resolved.timeout_seconds = entry.timeout_seconds;
  }
  return resolved;
}

function collectRequiredVerifierIds(policy: unknown): string[] {
  if (!isRecord(policy) || policy.mode !== "requirements" || !Array.isArray(policy.requirements)) {
    return [];
  }
  const seen = new Set<string>();
  const ids: string[] = [];
  for (const requirement of policy.requirements) {
    if (!isRecord(requirement) || !Array.isArray(requirement.required_verifiers)) {
      continue;
    }
    for (const id of requirement.required_verifiers) {
      if (typeof id === "string" && !seen.has(id)) {
        seen.add(id);
        ids.push(id);
      }
    }
  }
  return ids;
}

function extractVerifiers(policy: unknown): Record<string, unknown> {
  if (isRecord(policy) && isRecord(policy.verifiers)) {
    return policy.verifiers;
  }
  return {};
}

function substituteSlug(value: string, slug: string): string {
  return value.split(SLUG_TOKEN).join(slug);
}

function toStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
