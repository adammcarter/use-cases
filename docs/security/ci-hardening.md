# CI hardening: the CI-neutral authority contract & release-gate requirement

Use Case Matrix proofs record **where and how they were produced** in a
provider-agnostic `authority` block, and a repo can **require a minimum
authority** before a `required_for_release` row is allowed to ship. This page
covers the CI-neutral authority contract, the GitHub Actions reference path, how
other CI providers populate authority, and the release-gate authority
requirement.

> Authority is about **provenance**, not freshness. A row is `FRESH` when scan
> can verify a signed proof matching the current row / binding-set / verification
> context (see [key management](./key-management.md)). The `authority` block is
> **additive** and never changes that: legacy proofs minted before authority
> existed still validate and stay `FRESH`. Authority only matters when a repo
> **opts into** the release-gate requirement below.

## The CI-neutral authority contract

The trust model is **CI-neutral**: GitHub Actions is only the *reference*
provider. Every proof event may carry an OPTIONAL `authority` block
([`schemas/v1/authority.schema.json`](../../schemas/v1/authority.schema.json),
`$id: …/schemas/v1/authority.schema.json`) describing who/where minted it:

| Field | Meaning |
|---|---|
| `type` | `"ci"` when produced inside a recognised CI provider; `"local"` otherwise. |
| `provider` | `github-actions` \| `gitlab-ci` \| `circleci` \| `generic`. `generic` is the local / unrecognised fallback. |
| `repository` | Provider-shaped repo identifier (e.g. `owner/repo`). Best-effort. |
| `ref` | The git ref / branch the run executed against. Best-effort. |
| `commit` | The commit SHA the run executed against. Best-effort. |
| `run_id` | The provider's run / pipeline / build id. Best-effort. |
| `actor` | The login that triggered the run, when exposed. Best-effort. |
| `event` | The triggering event name (`push`, `pull_request`, `merge_request`, …). |
| `protected_ref` | **Tri-state**: `true`/`false` when the provider attests the protected-branch state, `null` when **unknown**. |

The block is built **into the event before signing**, so the signature covers it
— authority cannot be forged or altered after minting without breaking the
proof's signature. The existing GitHub-shaped `producer` block is unchanged;
`authority` is the CI-neutral trust record beside it.

> **Honest about `protected_ref`.** It is **provider-attested where available and
> otherwise unknown** (`null`). GitHub Actions does not expose a branch-protection
> signal in the runner environment, so the reference path reports `null` unless
> you supply the value out of band (see overrides below). GitLab CI exposes
> `CI_COMMIT_REF_PROTECTED` and is read directly. A `null` (unknown) value never
> satisfies a `require_protected_ref` gate — the gate fails closed.

## How authority is populated

`prove` fills the `authority` block automatically by auto-detecting the CI
environment (pure `detectCiAuthority(env)` in `markers/ciAuthority.ts`), or you
can supply it explicitly.

### GitHub Actions (the reference path)

Detected via `GITHUB_ACTIONS`. Fields are read from the standard runner env:

| Authority field | Env var |
|---|---|
| `repository` | `GITHUB_REPOSITORY` |
| `ref` | `GITHUB_REF` |
| `commit` | `GITHUB_SHA` |
| `run_id` | `GITHUB_RUN_ID` |
| `actor` | `GITHUB_ACTOR` |
| `event` | `GITHUB_EVENT_NAME` |
| `protected_ref` | unknowable from the runner env → `null` (override to set) |

No configuration is needed: running `ucm prove …` inside a GitHub Actions job
yields `type: "ci"`, `provider: "github-actions"`.

### Other CI providers (auto-detected)

The same auto-detection recognises:

- **GitLab CI** (`GITLAB_CI`): `CI_PROJECT_PATH`, `CI_COMMIT_REF_NAME`,
  `CI_COMMIT_SHA`, `CI_PIPELINE_ID`, `GITLAB_USER_LOGIN`, `CI_PIPELINE_SOURCE`,
  and the explicit `CI_COMMIT_REF_PROTECTED` → `protected_ref`.
- **CircleCI** (`CIRCLECI`): `CIRCLE_PROJECT_USERNAME`/`CIRCLE_PROJECT_REPONAME`
  → `owner/repo`, `CIRCLE_BRANCH`, `CIRCLE_SHA1`, `CIRCLE_BUILD_NUM`,
  `CIRCLE_USERNAME`. No protected-branch signal → `protected_ref: null`.
- **Anything else** → `{ type: "local", provider: "generic" }`.

### Unknown providers & overrides: `--authority-file`

For a CI provider that is not auto-detected, or to attest a value the runner
cannot expose (e.g. `protected_ref` on GitHub), pass a JSON authority record:

```sh
ucm prove --all --trusted-ci \
  --verification-results "$UCM_VERIFICATION_RESULTS" \
  --signing-key-env UCM_CI_SIGNING_KEY --key-id ci-key-1 \
  --authority-file authority.json
```

`--verification-results` is required — it is the unsigned results ledger written
earlier by `ucm verify --out "$UCM_VERIFICATION_RESULTS"`.

```json
{
  "type": "ci",
  "provider": "generic",
  "repository": "owner/repo",
  "ref": "refs/heads/main",
  "commit": "0123…",
  "run_id": "4242",
  "protected_ref": true
}
```

The file is validated against `authority.schema.json`, embedded, and signed.

## The release-gate authority requirement

By default the release gate does **not** look at authority — a `FRESH` required
row passes regardless of how it was proved. A repo can **opt in** to a minimum
authority via the OPTIONAL `release_gate` section of `use-case-matrix.yml`:

```yaml
# use-case-matrix.yml
release_gate:
  required_authority: ci        # matching proof must have authority.type === "ci"
  require_protected_ref: true   # ...and authority.protected_ref === true
```

Semantics, in **release mode only**:

- A `required_for_release` row whose only `FRESH` proof was minted with
  **insufficient authority** — `type: "local"` when `required_authority: ci`, or
  `protected_ref` not exactly `true` when `require_protected_ref: true`, or **no
  authority block at all** — is **POLICY-BLOCKED**. It is surfaced in the
  freshness / gate output with an `AUTHORITY_INSUFFICIENT` reason and counted in
  `summary.policy_blocked`.
- A required row that is already not `FRESH` is blocked exactly as before; the
  authority gate is **purely additive** — it can only ever block an
  *otherwise-`FRESH`* required row, never relax existing blocking.
- **Feature mode is never affected**, and non-`required_for_release` rows are
  never authority-blocked.
- **Off by default.** Omit `release_gate`, or leave its fields unset, and gating
  is exactly as it was — nothing changes for repos that do not configure it.

This is the hardening lever: require that everything you ship was proved by **CI
on a protected branch**, not on someone's laptop, while keeping the whole trust
model CI-neutral (any provider that produces a `type: "ci"` /
provider-attested-`protected_ref` proof satisfies the gate).
