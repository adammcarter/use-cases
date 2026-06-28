// Resolve the concrete verifier(s) a marker row's verification_policy demands.
//
// A verification_policy in "requirements" mode lists `required_verifiers` ids per
// requirement. Each id resolves to either (a) an explicit verifier declared under
// `policy.verifiers`, or (b) the default-convention "acceptance" verifier that
// runs the row's own use-case test. Anything else is returned BLOCKED rather than
// thrown, so callers can surface an actionable diagnostic instead of crashing.
//
// Pure + deterministic: given a row the result is sorted by verifier_id and
// deduped, and `{slug}` is substituted everywhere it appears in command/inputs.

export const DEFAULT_CONVENTION_VERIFIER_ID = "acceptance";

const SLUG_TOKEN = "{slug}";

// The default-convention "acceptance" verifier: run the row's own use-case test.
const DEFAULT_CONVENTION_COMMAND = [
  "pnpm",
  "-s",
  "vitest",
  "run",
  "tests/use-cases/{slug}.test.ts"
];
const DEFAULT_CONVENTION_INPUTS = ["tests/use-cases/{slug}.test.ts"];

// The minimal row shape this resolver needs: a slug (the row/use-case id, used to
// substitute {slug}) plus the raw verification_policy object.
export interface VerifierResolverRow {
  slug: string;
  verification_policy: unknown;
}

export interface ResolvedVerifier {
  verifier_id: string;
  status: "resolved";
  source: "policy" | "default_convention";
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
export function resolveRowVerifiers(row: VerifierResolverRow): VerifierResolution[] {
  const ids = collectRequiredVerifierIds(row.verification_policy);
  const verifiers = extractVerifiers(row.verification_policy);
  return ids
    .map((id) => resolveOne(id, row.slug, verifiers))
    .sort((left, right) =>
      left.verifier_id < right.verifier_id ? -1 : left.verifier_id > right.verifier_id ? 1 : 0
    );
}

function resolveOne(
  id: string,
  slug: string,
  verifiers: Record<string, unknown>
): VerifierResolution {
  const declared = verifiers[id];
  if (isRecord(declared)) {
    return resolveDeclared(id, slug, declared);
  }
  if (id === DEFAULT_CONVENTION_VERIFIER_ID) {
    return defaultConventionVerifier(id, slug);
  }
  return {
    verifier_id: id,
    status: "blocked",
    reason: `verifier '${id}' is not declared in verification_policy.verifiers and is not the default-convention id '${DEFAULT_CONVENTION_VERIFIER_ID}'`
  };
}

function resolveDeclared(
  id: string,
  slug: string,
  declared: Record<string, unknown>
): ResolvedVerifier {
  const resolved: ResolvedVerifier = {
    verifier_id: id,
    status: "resolved",
    source: "policy",
    kind: "script",
    evidence_kind:
      typeof declared.evidence_kind === "string" ? declared.evidence_kind : "test_result",
    command: toStringArray(declared.command).map((part) => substituteSlug(part, slug)),
    inputs: toStringArray(declared.inputs).map((part) => substituteSlug(part, slug))
  };
  if (typeof declared.timeout_seconds === "number") {
    resolved.timeout_seconds = declared.timeout_seconds;
  }
  return resolved;
}

function defaultConventionVerifier(id: string, slug: string): ResolvedVerifier {
  return {
    verifier_id: id,
    status: "resolved",
    source: "default_convention",
    kind: "script",
    evidence_kind: "test_result",
    command: DEFAULT_CONVENTION_COMMAND.map((part) => substituteSlug(part, slug)),
    inputs: DEFAULT_CONVENTION_INPUTS.map((part) => substituteSlug(part, slug))
  };
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
