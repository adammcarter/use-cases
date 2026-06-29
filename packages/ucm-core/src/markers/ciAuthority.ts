// CI-neutral provenance authority detection (public-v1, Phase 2).
//
// The trust model is CI-NEUTRAL: GitHub Actions is only the reference provider.
// `detectCiAuthority` reads a provider-agnostic `CiAuthority` record off a CI
// environment map — recognising GitHub Actions, GitLab CI, and CircleCI — and
// falls back to a `local` / `generic` record when no CI is present.
//
// It is PURE: the environment is passed in (never read from process.env here),
// so callers (the `prove` CLI) own the impurity and tests stay deterministic.
//
// The record is OPTIONAL and ADDITIVE on a proof event: it does not influence
// freshness (FRESH matches row/binding/context hashes, not provenance). When the
// `prove` command embeds it, it is built INTO the event before signing, so the
// signature covers it. The shape mirrors schemas/v1/authority.schema.json.

// A provider-agnostic provenance authority record (mirrors
// schemas/v1/authority.schema.json). Optional string fields are OMITTED (not set
// to undefined explicitly in the emitted JSON) when their source signal is
// absent; `protected_ref` is a tri-state (true/false/null) where null = unknown.
export interface CiAuthority {
  type: "ci" | "local";
  provider: "github-actions" | "gitlab-ci" | "circleci" | "generic";
  repository?: string;
  ref?: string;
  commit?: string;
  run_id?: string;
  actor?: string;
  protected_ref?: boolean | null;
  event?: string;
}

// A read-only environment map (a subset of process.env). Values may be undefined.
export type CiEnv = Readonly<Record<string, string | undefined>>;

export interface DetectCiAuthorityOptions {
  // Force the protected_ref tri-state, overriding any provider signal. Use when a
  // caller knows the branch-protection state out of band (null = explicitly
  // unknown). Omit to use the provider's best-effort signal.
  protectedRef?: boolean | null;
}

// A non-empty trimmed string, or undefined. Used to omit absent optional fields.
function str(value: string | undefined): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

// Parse a provider's boolean-ish protected-branch signal into the tri-state:
// "true" -> true, "false" -> false, anything else (incl. absent) -> null.
function triBool(value: string | undefined): boolean | null {
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  return null;
}

// Assemble a record, dropping optional fields whose value is undefined so the
// emitted authority block carries only fields that are actually present.
function build(record: CiAuthority): CiAuthority {
  const out: CiAuthority = { type: record.type, provider: record.provider };
  if (record.repository !== undefined) out.repository = record.repository;
  if (record.ref !== undefined) out.ref = record.ref;
  if (record.commit !== undefined) out.commit = record.commit;
  if (record.run_id !== undefined) out.run_id = record.run_id;
  if (record.actor !== undefined) out.actor = record.actor;
  if (record.protected_ref !== undefined) out.protected_ref = record.protected_ref;
  if (record.event !== undefined) out.event = record.event;
  return out;
}

// Is this a GitHub Actions environment? GITHUB_ACTIONS is set to "true" on every
// runner; we also accept its mere presence defensively.
function isGitHubActions(env: CiEnv): boolean {
  return env.GITHUB_ACTIONS !== undefined && env.GITHUB_ACTIONS !== "";
}

function isGitLabCi(env: CiEnv): boolean {
  return env.GITLAB_CI !== undefined && env.GITLAB_CI !== "";
}

function isCircleCi(env: CiEnv): boolean {
  return env.CIRCLECI !== undefined && env.CIRCLECI !== "";
}

// Detect the CI-neutral provenance authority from an environment map.
//
//   - GitHub Actions (GITHUB_ACTIONS): repository/ref/commit/run_id/actor/event
//     from GITHUB_REPOSITORY/GITHUB_REF/GITHUB_SHA/GITHUB_RUN_ID/GITHUB_ACTOR/
//     GITHUB_EVENT_NAME. protected_ref is unknowable from the runner env, so it
//     is null unless an explicit override is supplied.
//   - GitLab CI (GITLAB_CI): CI_PROJECT_PATH/CI_COMMIT_REF_NAME/CI_COMMIT_SHA/
//     CI_PIPELINE_ID/GITLAB_USER_LOGIN, event from CI_PIPELINE_SOURCE.
//     protected_ref reads GitLab's explicit CI_COMMIT_REF_PROTECTED signal.
//   - CircleCI (CIRCLECI): CIRCLE_PROJECT_USERNAME/CIRCLE_PROJECT_REPONAME ->
//     "owner/repo", CIRCLE_BRANCH/CIRCLE_SHA1/CIRCLE_BUILD_NUM/CIRCLE_USERNAME.
//     protected_ref is null (no signal).
//   - otherwise -> { type: "local", provider: "generic" }.
//
// `options.protectedRef`, when provided, overrides the detected tri-state.
export function detectCiAuthority(env: CiEnv, options: DetectCiAuthorityOptions = {}): CiAuthority {
  const overrideProtected = Object.prototype.hasOwnProperty.call(options, "protectedRef");

  if (isGitHubActions(env)) {
    return build({
      type: "ci",
      provider: "github-actions",
      repository: str(env.GITHUB_REPOSITORY),
      ref: str(env.GITHUB_REF),
      commit: str(env.GITHUB_SHA),
      run_id: str(env.GITHUB_RUN_ID),
      actor: str(env.GITHUB_ACTOR),
      protected_ref: overrideProtected ? options.protectedRef : null,
      event: str(env.GITHUB_EVENT_NAME)
    });
  }

  if (isGitLabCi(env)) {
    return build({
      type: "ci",
      provider: "gitlab-ci",
      repository: str(env.CI_PROJECT_PATH),
      ref: str(env.CI_COMMIT_REF_NAME),
      commit: str(env.CI_COMMIT_SHA),
      run_id: str(env.CI_PIPELINE_ID),
      actor: str(env.GITLAB_USER_LOGIN),
      protected_ref: overrideProtected
        ? options.protectedRef
        : triBool(env.CI_COMMIT_REF_PROTECTED),
      event: str(env.CI_PIPELINE_SOURCE)
    });
  }

  if (isCircleCi(env)) {
    const owner = str(env.CIRCLE_PROJECT_USERNAME);
    const repo = str(env.CIRCLE_PROJECT_REPONAME);
    const repository = owner && repo ? `${owner}/${repo}` : (repo ?? owner);
    return build({
      type: "ci",
      provider: "circleci",
      repository,
      ref: str(env.CIRCLE_BRANCH),
      commit: str(env.CIRCLE_SHA1),
      run_id: str(env.CIRCLE_BUILD_NUM),
      actor: str(env.CIRCLE_USERNAME),
      protected_ref: overrideProtected ? options.protectedRef : null
    });
  }

  return build({
    type: "local",
    provider: "generic",
    protected_ref: overrideProtected ? options.protectedRef : undefined
  });
}
