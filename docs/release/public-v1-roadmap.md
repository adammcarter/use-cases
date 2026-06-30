# Public v1 Roadmap — Use Cases Plugin (UCM)

> **Historical planning document.** This roadmap captures the *proposed* design as
> it was being built. Some command names and flags here are illustrative
> proposals and do **not** all match the shipped CLI — run `ucp --help` for the
> authoritative command surface, and see [docs/cli.md](../cli.md). Kept for
> provenance, not as a current reference.

> Canonical program of work to take this project from a working internal trust
> engine to a **public v1 anyone can adopt**. Owner directive: full surface, no
> corners cut. Designed with deep-reasoning review (Albus/ChatGPT Pro). This file
> is the source of truth for v1 scope, contracts, and sequencing.

**Name:** Use Cases Plugin (UCM) · npm scope `@use-cases-plugin/{core,cli,mcp}` · CLI `ucp` (alias `use-cases-plugin`) · MCP `ucp-mcp`.

Phases (tracked as tasks): 0 Rename+contracts · 1 Schema/API · 2 Trust-core · 3 Lifecycle surfaces · 4 CLI+MCP · 5 Dogfood+examples+docs · 6 Supply-chain+release.

---

## Bottom line

The owner’s correction changes the release shape from “trust-core public v1 + lifecycle labs” to **full-surface public v1**. That means the work is no longer mainly product pruning; it is a **contract hardening, generalisation, security, documentation, and release-engineering program**.

My recommendation is:

**Ship as “Use Cases Plugin” / “UCM”, not “use-cases-plugin”.**  
Use package scope **`@use-cases-plugin/*`**, primary CLI binary **`ucp`**, MCP package **`@use-cases-plugin/mcp`**, and treat every surface as a versioned public contract.

A v1 is only credible when a new repo can install from packed tarballs, run `ucp init`, bind at least one row, run a configured verifier that is not pnpm/vitest-specific, produce a signed proof, see `FRESH`, run the release gate, run showcase/evidence/capsule/plan/host workflows, and drive the same surface through MCP.

---

## External anchors I would treat as release constraints

A few current ecosystem constraints matter for this plan:

npm Trusted Publishing now lets packages publish from supported CI systems using OIDC instead of long-lived npm tokens; npm’s docs currently list GitHub Actions, GitLab CI/CD, and CircleCI cloud, and also state that self-hosted runners are not currently supported for that feature. The same docs state Trusted Publishing requires npm CLI `11.5.1+` and Node `22.14.0+` for the publishing workflow. citeturn944347view0

npm provenance docs say Trusted Publishing generates provenance attestations automatically, while manual provenance publishing still requires the usual CI permissions such as `id-token: write` and a cloud-hosted runner. Use this for package release, but keep your **UCM proof ledger** separate; npm provenance proves package build origin, not row-level use-case freshness. citeturn944347view1

SemVer `1.0.0` explicitly defines the public API, and later breaking public API changes require a major version. For UCM, “public API” must include TypeScript exports, schema files, config formats, CLI JSON, exit codes, MCP tool/resource/prompt names, proof ledger format, matrix format, and evidence/showcase/capsule/plan/host schemas. citeturn396727view5

The current MCP latest spec line found in official docs is `2025-11-25`; the spec defines MCP as an open protocol for connecting LLM applications to external data sources and tools. The official MCP tooling surface matters because UCM is agent-facing, and the server must not be a loose wrapper around arbitrary shell execution. citeturn479806search0turn944347view2

MCP’s tool security section says servers must validate tool inputs, implement access controls, rate-limit invocations, and sanitize outputs. That should be a hard UCM MCP v1 gate. citeturn944347view3

For HTTP-based MCP, the authorization spec requires OAuth 2.1-oriented security, protected resource metadata, secure token storage, HTTPS for authorization endpoints, and PKCE support. For v1, I would ship the UCM MCP server as **local stdio-first** and explicitly defer remote HTTP hosting unless you implement this properly. citeturn944347view5

The MCP Registry is currently described as preview, with possible breaking changes or data resets. It hosts metadata, not artifacts, and npm package publication must happen first; npm package ownership verification currently uses an `mcpName` property matching `server.json`. Publish there only after npm publication, and do not make registry availability part of the core product guarantee. citeturn396727view0turn396727view3

GitHub artifact attestations create signed claims about build provenance, including workflow, repository, commit SHA, and other OIDC-derived information; GitHub notes the security benefit only materializes when consumers verify attestations. Use attestations for release artifacts and ledger bundles. citeturn944347view6

---

# 1. Product architecture stance for public v1

## Product definition

**Use Cases Plugin** is a repo-local, agent-facing assurance system for keeping product claims, code spans, demonstrations, evidence, and release decisions aligned.

The system has four layers:

1. **Authoring layer**  
   Matrix rows, markers, bindings, plans, host profiles, showcase specs.

2. **Evidence layer**  
   Evidence records, showcase run artifacts, capsules, proof entries, void events.

3. **Trust layer**  
   Verification policy, signed proofs, ledger integrity, freshness derivation, release gate.

4. **Agent layer**  
   CLI and MCP server expose the full workflow to coding agents without needing a GUI.

## Canonical repo layout

Use one predictable root directory. I would use `.ucp/` rather than scattering files.

```text
.ucp/
  matrix.yaml
  config.yaml
  bindings.jsonl
  ledger.jsonl
  evidence/
    events.jsonl
    artifacts/
  showcase/
    specs/
    runs/
  capsule/
    generated/
  plan/
    generated/
  host/
    profiles/
  schemas/
    v1/
```

Generated derivative docs can live elsewhere, but the canonical state should be machine-readable and schema-validated.

## Public contract envelope

Every CLI JSON response and MCP structured result should use the same envelope:

```json
{
  "schemaVersion": "ucp/v1",
  "ucmVersion": "1.0.0",
  "command": "freshness",
  "ok": true,
  "data": {},
  "warnings": [],
  "errors": [],
  "meta": {
    "cwd": "/repo",
    "gitCommit": "abc123",
    "generatedAt": "2026-06-28T12:00:00.000Z"
  }
}
```

Hard rule: **human output may evolve; JSON output is public API.**

## Stable error model

Use stable machine-readable codes everywhere:

```json
{
  "code": "UCP_BINDING_MARKER_DUPLICATE",
  "message": "Two markers declare the same binding id.",
  "severity": "error",
  "surface": "binding",
  "path": "src/foo.ts",
  "rowId": "row.checkout.happy-path",
  "docs": "errors/UCP_BINDING_MARKER_DUPLICATE"
}
```

Do not let each surface invent its own errors.

---

# 2. Naming decision

## Final recommendation

Use:

**Product name:** `Use Cases Plugin`  
**Short name:** `UCM`  
**NPM scope:** `@use-cases-plugin`  
**CLI primary binary:** `ucp`  
**CLI long binary alias:** `use-cases-plugin`  
**MCP server binary:** `ucp-mcp`  
**Long MCP alias:** `use-cases-plugin-mcp`

Do **not** call it `use-cases-plugin`.

## Why this is the right call

`use-cases-plugin` is weaker for public adoption because:

- It sounds like an extension to some unnamed host.
- “Plugin” undersells the trust engine and release gate.
- It does not describe the artifact users work with.
- It is awkward as a package namespace.
- It makes the MCP server sound secondary rather than first-class.

`Use Cases Plugin` is better because:

- It names the central object.
- It leaves room for CLI, MCP, ledger, evidence, and showcase without sounding host-specific.
- `UCM` is short enough for commands, markers, and docs.
- It is neutral across JS, Python, Go, docs-only repos, and agent hosts.

## Exact package names

Use:

```text
@use-cases-plugin/core
@use-cases-plugin/cli
@use-cases-plugin/mcp
```

Keep package count low for v1. Do not split showcase/evidence/host into separate packages yet unless consumers truly need direct imports. Internal modules can remain separate inside `core`.

## Exact binaries

`@use-cases-plugin/cli`:

```json
{
  "bin": {
    "ucp": "./dist/bin/ucp.js",
    "use-cases-plugin": "./dist/bin/ucp.js"
  }
}
```

`@use-cases-plugin/mcp`:

```json
{
  "bin": {
    "ucp-mcp": "./dist/bin/ucp-mcp.js",
    "use-cases-plugin-mcp": "./dist/bin/ucp-mcp.js"
  }
}
```

## Config and schema naming

Use:

```text
.ucp/config.yaml
.ucp/matrix.yaml
```

Also accept, but do not prefer:

```text
ucp.config.yaml
ucp.config.json
```

Schema IDs should be stable. Example:

```json
{
  "$id": "https://use-cases-plugin.dev/schemas/v1/matrix.schema.json",
  "$schema": "https://json-schema.org/draft/2020-12/schema"
}
```

If the domain is not ready, publish schemas from the package and docs site first, but reserve the final `$id` now so you do not break v1 later.

## Lowest-risk pre-publish rename path

1. **Create a rename branch before public docs are written.**
2. **Rename package names and imports in one mechanical PR.**
   - `@presentation-skills/core` → `@use-cases-plugin/core`
   - `@presentation-skills/cli` → `@use-cases-plugin/cli`
   - `@presentation-skills/mcp` → `@use-cases-plugin/mcp`
3. **Rename internal docs, generated help, examples, schema `$id`s, MCP names, CLI help, and fixtures in the same PR.**
4. **Keep internal folder names boring:**
   - `packages/core`
   - `packages/cli`
   - `packages/mcp`
5. **Run a codemod check in CI** that fails if `presentation-skills`, `use-cases-plugin`, or old package names appear outside a migration note.
6. **Pack before publish:**
   - `pnpm -r build`
   - `pnpm -r test`
   - `pnpm -r pack`
   - install packed tarballs into fresh fixtures.
7. **Publish `1.0.0-rc.1` first**, dogfood it from npm or packed tarballs, then publish `1.0.0`.
8. Since the old packages are unpublished, do **not** publish compatibility shims. Avoid creating permanent names you do not want to support.

---

# 3. Per-surface public v1 readiness specs

## 3.1 Matrix

### Public contract

The matrix is the canonical list of product claims/use cases.

Minimum row schema:

```yaml
schemaVersion: ucp/matrix/v1
rows:
  - id: trust.fresh-row
    title: Freshness is only granted by a valid signed proof
    summary: A bound row is FRESH only when its proof, binding, span, and verification context still match.
    surface: freshness
    kind: behavior
    required_for_release: true
    tags: [trust, release]
    acceptance:
      - verifier: trust-engine-tests
    bindings:
      mode: required
    evidence:
      required: false
```

Required row fields:

- `id`
- `title`
- `summary`
- `surface`
- `kind`
- `required_for_release`
- `acceptance`
- `bindings.mode`

Optional but public fields:

- `tags`
- `hostApplicability`
- `showcase`
- `capsule`
- `plan`
- `owners`
- `risk`
- `stability`
- `notes`

Do **not** store `freshness` in the matrix. Freshness is derived.

### Generalisation bar

The matrix must not assume:

- TypeScript.
- pnpm.
- vitest.
- GitHub Actions.
- a specific directory layout.
- that every row maps to code rather than docs, tests, demos, schemas, configs, or examples.

Use row-level binding modes:

```yaml
bindings:
  mode: required | optional | none | external
```

Examples:

- `required`: a code/test/doc span must be bound.
- `external`: row binds to an external artifact or evidence record.
- `none`: conceptual/documentation rows that are intentionally not bindable.
- `optional`: useful for broad roadmap rows, but these should not usually be `required_for_release`.

### Test requirements

- Schema validation tests for valid and invalid rows.
- Duplicate ID rejection.
- Canonical hash stability tests.
- Windows/POSIX path normalization tests.
- Unicode and line-ending normalization tests.
- Migration tests from current internal format.
- Large matrix performance test.
- Deterministic sort/normalize test.
- “No manual freshness field” rejection test.
- “Every public command/tool has a row” coverage test.

### Docs/examples

- Matrix concept guide.
- Row authoring reference.
- `required_for_release` guide.
- Examples for:
  - TypeScript package.
  - Python package.
  - Go package.
  - docs-only repo.
  - MCP server repo.

### Definition of done

Matrix is v1-stable when a clean repo can run:

```bash
ucp init
ucp matrix check --json
ucp matrix normalize --check
```

…and get deterministic, schema-valid output without TypeScript, pnpm, or vitest being present.

---

## 3.2 Markers and bindings

### Public contract

Markers bind matrix rows to repository spans.

Use a language-neutral marker grammar wrapped in each language’s comment syntax:

```text
UCM:BEGIN row=<rowId> binding=<bindingId> role=<impl|test|doc|demo|config|schema>
...
UCM:END row=<rowId> binding=<bindingId>
```

Examples:

```ts
// UCM:BEGIN row=trust.fresh-row binding=trust-fresh-impl role=impl
export function deriveFreshness(...) {}
// UCM:END row=trust.fresh-row binding=trust-fresh-impl
```

```py
# UCM:BEGIN row=trust.fresh-row binding=trust-fresh-py-fixture role=test
def test_freshness_requires_signed_proof():
    ...
# UCM:END row=trust.fresh-row binding=trust-fresh-py-fixture
```

```md
<!-- UCM:BEGIN row=docs.quickstart binding=quickstart-doc role=doc -->
...
<!-- UCM:END row=docs.quickstart binding=quickstart-doc -->
```

Binding record schema:

```json
{
  "schemaVersion": "ucp/binding/v1",
  "rowId": "trust.fresh-row",
  "bindingId": "trust-fresh-impl",
  "role": "impl",
  "path": "packages/core/src/freshness.ts",
  "span": {
    "startLine": 12,
    "endLine": 44,
    "contentHash": "sha256:..."
  },
  "markerHash": "sha256:...",
  "bindingHash": "sha256:..."
}
```

Line numbers are hints. Hashes are authoritative.

### Generalisation bar

Must support:

- `//`, `#`, `--`, `;`, `<!-- -->`, `/* */`, `"""`, and custom comment wrappers.
- code, docs, YAML, JSON-with-external-binding, shell scripts, Markdown, CI files.
- CRLF and LF.
- moved files.
- generated files, if explicitly allowed.
- external artifacts that cannot carry markers.

Must reject or warn on:

- duplicate binding IDs.
- duplicate row spans with ambiguous role.
- missing end markers.
- nested marker ambiguity.
- path traversal.
- symlink escape from repo root.
- binary files unless externally bound.

### Test requirements

- Marker parser fixture suite across at least TS, Python, Go, Rust, Markdown, YAML, shell.
- Duplicate and malformed marker tests.
- CRLF normalization tests.
- Unicode tests.
- Path traversal/symlink tests.
- Bind scan/update idempotence tests.
- Span hash tamper tests.
- External binding tests.
- Moved file detection tests.

### Docs/examples

- Marker grammar.
- Supported comment styles.
- Binding lifecycle.
- “Binding tests vs implementation vs docs.”
- “What to bind for broad use cases.”
- “How to bind non-code assets.”

### Definition of done

A non-JS fixture can add markers, run:

```bash
ucp bind scan
ucp bind check --json
```

…and get stable bindings with no pnpm/vitest assumptions.

---

## 3.3 Verify/prove trust engine and ledger

### Public contract

There are two distinct operations:

```text
verify = run configured checks, compute status, never sign, never require key
prove  = run configured checks, sign successful verification, append proof to ledger
```

`verify` is safe on PRs.  
`prove` is restricted to trusted authority contexts.

Proof entry schema:

```json
{
  "schemaVersion": "ucp/proof/v1",
  "entryIndex": 42,
  "previousEntryHash": "sha256:...",
  "entryHash": "sha256:...",
  "subject": {
    "gitCommit": "abc123",
    "matrixHash": "sha256:...",
    "rowHash": "sha256:...",
    "bindingHash": "sha256:...",
    "spanHash": "sha256:...",
    "verificationContextHash": "sha256:..."
  },
  "verifier": {
    "id": "core-tests",
    "type": "command",
    "commandHash": "sha256:...",
    "policyHash": "sha256:...",
    "exitCode": 0,
    "stdoutHash": "sha256:...",
    "stderrHash": "sha256:..."
  },
  "authority": {
    "type": "github-actions",
    "runId": "123456789",
    "ref": "refs/heads/main",
    "protectedRef": true
  },
  "signature": {
    "algorithm": "ed25519",
    "keyId": "release-2026-q3",
    "signature": "base64..."
  },
  "createdAt": "2026-06-28T12:00:00.000Z"
}
```

### Ledger integrity bar

Do not claim “append-only” without qualification.

A file in a Git repo is not physically append-only. Public v1 should call it:

> **tamper-evident append-only ledger**

Minimum hardening:

- JSONL entries.
- monotonic `entryIndex`.
- `previousEntryHash`.
- canonical entry hashing.
- signature over all material fields.
- keyring with key IDs.
- key validity windows.
- key revocation support.
- refusal on edited, reordered, duplicated, or truncated entries when a trusted checkpoint exists.
- signed release checkpoints.
- CI artifact attestation for release ledger bundle.

Without an external checkpoint, history rewrite can remove later valid entries. With Git branch protection, signed tags, release attestations, and checkpoints, the system becomes substantially stronger. Be honest about that in docs.

### Generalisation bar

The verifier model must be language-neutral.

Core verifier type:

```yaml
verifiers:
  core-tests:
    type: command
    command:
      argv: ["npm", "test"]
    cwd: "."
    timeoutSeconds: 120
    env:
      allow:
        - CI
        - NODE_ENV
    success:
      exitCode: 0
```

Presets may exist, but only as adapters:

```yaml
presets:
  - id: js.pnpm.vitest
  - id: js.npm.test
  - id: python.pytest
  - id: go.test
  - id: rust.cargo-test
  - id: make.target
```

Core must not default to pnpm/vitest. `pnpm+vitest` is one preset.

### CI-neutral proof authority contract

GitHub Actions can be first-class, but not the only model.

Support:

```yaml
authority:
  type: ci
  provider: github-actions | gitlab-ci | circleci | buildkite | generic
  repository: string
  ref: string
  commit: string
  runId: string
  actor: string
  protectedRef: boolean | unknown
  event: string
```

For unknown CI, allow:

```bash
ucp prove --authority-file ./authority.json
```

…but let release policy reject low-assurance authorities.

### Prove-job hardening

Public v1 bar:

- `verify` runs on PRs with no signing key.
- `prove` runs only on protected branches or protected release tags.
- signing key is only available in a protected environment.
- no prove on forked PRs.
- no prove with dirty worktree except ledger output.
- no prove if matrix/config changed without verify rerun.
- no prove with unpinned verifier definitions.
- no prove if the subject commit differs from the checked-out source commit.
- proof commit records `subjectGitCommit`.
- release gate validates the proof against current source state, not merely latest ledger entry.
- proof writeback is done by bot PR or tightly scoped bot push, not a broad personal token.

### Test requirements

- Signature verification.
- Invalid signature rejection.
- Wrong key rejection.
- Hash mismatch rejection.
- Context hash mismatch.
- Chain tampering.
- Ledger truncation with checkpoint.
- Duplicate entry.
- Reordered entries.
- `verify` does not write.
- `prove` refuses without key.
- `prove` refuses untrusted authority when policy requires CI.
- Key rotation.
- Key revocation.
- Command argv escaping.
- Shell-injection tests.
- Timeout tests.
- Env allowlist tests.
- Non-JS verifier fixtures.

### Docs/examples

- Trust model.
- Ledger model.
- “Tamper-evident, not magic.”
- Key generation and rotation.
- CI recipes:
  - GitHub Actions.
  - generic CI.
  - GitLab/CircleCI examples if you want parity with npm Trusted Publishing providers.
- Verifier authoring guide.
- Threat model.

### Definition of done

A clean Python or Go fixture can configure a command verifier, run `verify`, run `prove` with an ed25519 test key, and get a valid FRESH row with no JS toolchain installed.

---

## 3.4 Freshness

### Public contract

Freshness is derived, never manually set.

Statuses:

```text
FRESH
SUSPECT
UNPROVEN
UNBOUND
INVALID
```

Recommended precedence:

1. `INVALID` — row, config, binding, ledger, or evidence cannot be parsed or violates schema.
2. `UNBOUND` — row requires binding but has no valid binding.
3. `SUSPECT` — a proof exists, but row/binding/span/context/key/ledger no longer validates.
4. `UNPROVEN` — row and binding are valid, but no valid proof exists.
5. `FRESH` — valid proof exists and all hashes/signatures/context match.

Freshness result schema:

```json
{
  "rowId": "trust.fresh-row",
  "freshness": "FRESH",
  "reasons": [
    {
      "code": "UCP_FRESH_VALID_PROOF",
      "proofEntryHash": "sha256:..."
    }
  ],
  "checked": {
    "rowHash": "sha256:...",
    "bindingHash": "sha256:...",
    "spanHash": "sha256:...",
    "verificationContextHash": "sha256:..."
  }
}
```

### Generalisation bar

Must handle:

- rows with multiple bindings.
- rows with no binding by design.
- external binding rows.
- multiple proofs for the same row.
- old proofs after verifier policy changes.
- key rotation.
- release-gate policy requiring only certain rows.
- local proofs that are valid but lower-assurance than CI proofs.

### Test requirements

- Complete transition matrix.
- Multiple proof selection.
- Policy-change → `SUSPECT`.
- Span edit → `SUSPECT`.
- Row edit → `SUSPECT`.
- Binding moved but same content → expected behavior defined and tested.
- Key revoked → `SUSPECT` or `INVALID`, depending on policy.
- Missing ledger → `UNPROVEN`.
- Required binding missing → `UNBOUND`.
- Malformed row → `INVALID`.

### Docs/examples

- Freshness status reference.
- “Why did my row become SUSPECT?”
- “How to get back to FRESH.”
- “Local proof vs CI proof.”

### Definition of done

`ucp freshness --json` gives deterministic per-row status with stable reason codes, and every reason points to an actionable fix.

---

## 3.5 Release gate

### Public contract

Release gate answers:

> “Can this repo publish or release under the declared v1 policy?”

Gate config:

```yaml
releaseGate:
  requiredStatus: FRESH
  requiredAuthority: ci
  includeRows:
    required_for_release: true
  evidence:
    requireActiveEvidenceForKinds:
      - showcase
  allowWaivers: false
```

CLI:

```bash
ucp gate
ucp gate --json
ucp gate --changed-since origin/main
```

Exit codes:

```text
0 = pass
1 = gate failed
2 = invalid config/input
3 = internal error
4 = security/policy refusal
```

### Generalisation bar

Must not assume:

- GitHub Actions.
- npm.
- pnpm.
- vitest.
- Node package release.
- one matrix file path unless configured.

GitHub annotations are useful, but optional.

### Test requirements

- Required row `FRESH` passes.
- Required row `UNPROVEN` fails.
- Required row `SUSPECT` fails.
- Non-required row does not fail default policy.
- Invalid matrix fails.
- Required showcase/evidence missing fails if configured.
- Waiver disabled means waiver is ignored.
- Waiver enabled requires reason, owner, expiry, and linked evidence.
- CI-neutral JSON output.

### Docs/examples

- Release policy guide.
- GitHub Actions gate recipe.
- CI-neutral shell recipe.
- “What should be required_for_release?”
- “How to use waivers without destroying trust.”

### Definition of done

The repository’s own release pipeline cannot publish unless all v1-required rows are FRESH under the configured authority policy.

---

## 3.6 Showcase

### Public contract

Showcase is a live, agent-driven demo run system. It must produce durable, inspectable artifacts.

Showcase spec:

```yaml
schemaVersion: ucp/showcase-spec/v1
id: cli.first-fresh
title: First FRESH row from a clean repo
rows:
  - onboarding.first-fresh
runner:
  type: agent
  adapter: local-mcp-client
  timeoutSeconds: 600
environment:
  network: disabled
  filesystem: temp-repo
  secrets: none
steps:
  - goal: Initialize UCM
  - goal: Bind one row
  - goal: Verify and prove
checkpoints:
  - type: command
    argv: ["ucp", "freshness", "--json"]
    expect:
      jsonPath: "$.data.rows[0].freshness"
      equals: "FRESH"
artifacts:
  keep:
    - transcript
    - commands
    - stdout
    - stderr
    - generated-files
redaction:
  enabled: true
```

Showcase run result:

```json
{
  "schemaVersion": "ucp/showcase-run/v1",
  "runId": "showcase_20260628_abc",
  "specId": "cli.first-fresh",
  "status": "passed",
  "rowIds": ["onboarding.first-fresh"],
  "artifacts": [
    {
      "kind": "transcript",
      "path": ".ucp/showcase/runs/.../transcript.md",
      "sha256": "..."
    }
  ]
}
```

### Generalisation bar

Showcase must not assume:

- your repo.
- TypeScript.
- pnpm.
- vitest.
- a specific LLM provider.
- a GUI.
- network access.
- GitHub Actions.

Use pluggable runner types:

```text
agent        = real agent/host adapter
scripted     = deterministic command script
mcp-client   = local MCP client harness
manual       = records externally produced artifacts
```

For public v1, the **surface** must support agent-driven runs, but the **test suite** should use deterministic fake/local adapters so CI is stable.

### Security bar

- no arbitrary command execution from matrix row text.
- only configured commands/tools.
- network disabled by default.
- temp workspace by default.
- strict timeout.
- transcript redaction.
- secret-pattern scanning.
- artifact hashing.
- voidable evidence records for bad runs.
- clear flaky-run classification.

### Test requirements

- Fake agent happy path.
- Failing checkpoint.
- Timeout.
- Redaction.
- Artifact hash verification.
- Network-disabled behavior.
- Non-JS fixture showcase.
- MCP-driven showcase.
- Replay/status command.
- Voiding a showcase evidence record.

### Docs/examples

- Showcase concept.
- Writing showcase specs.
- Agent adapters.
- CI showcase runs.
- Interpreting showcase artifacts.
- Redaction and privacy.

### Definition of done

A user can run:

```bash
ucp showcase run cli.first-fresh --json
ucp showcase status --json
```

…and get a durable run artifact linked to rows and evidence, with deterministic status and no repo-specific assumptions.

---

## 3.7 Capsule

### Public contract

Capsule is the compact, agent-consumable state package for a repo or selected rows.

It should output both:

```text
capsule.json
capsule.md
```

Capsule schema:

```json
{
  "schemaVersion": "ucp/capsule/v1",
  "id": "release-review",
  "scope": {
    "rows": ["trust.fresh-row"],
    "surfaces": ["matrix", "freshness", "release-gate"]
  },
  "summary": {},
  "freshness": {},
  "evidence": {},
  "showcases": {},
  "recommendedAgentActions": []
}
```

### Generalisation bar

Capsule must be:

- deterministic.
- bounded by token/size budget.
- independent of JS package metadata.
- usable for any repo type.
- explicit about omitted content.
- linked to source hashes so stale capsules can be detected.

### Test requirements

- Deterministic generation.
- Size budget enforcement.
- Link validity.
- Staleness detection.
- Redaction.
- Large matrix summarization.
- Non-JS fixture.
- JSON/Markdown consistency.

### Docs/examples

- “What is a capsule?”
- “Give this capsule to an agent.”
- Capsule schema.
- Capsule generation examples.
- Capsule staleness model.

### Definition of done

A capsule can be generated from the repo, consumed by an agent, and traced back to the exact rows/evidence/freshness snapshot it summarizes.

---

## 3.8 Plan

### Public contract

Plan is the structured work plan surface: showcase plans, walkthroughs, and cards.

Plan schema:

```yaml
schemaVersion: ucp/plan/v1
id: public-v1-hardening
title: Public v1 hardening plan
scope:
  surfaces: [cli, mcp, evidence]
cards:
  - id: cli-json-contract
    title: Stabilize CLI JSON envelope
    rows:
      - cli.json-contract
    status: todo
    acceptance:
      - verifier: cli-contract-tests
walkthrough:
  - card: cli-json-contract
    action: Run CLI contract tests
```

### Generalisation bar

Plan must not be a freeform markdown blob. Markdown can be generated, but canonical plan state should be structured.

Must support:

- cards.
- walkthrough steps.
- linked rows.
- linked showcase specs.
- acceptance criteria.
- evidence requirements.
- status transitions.
- generated docs.

### Test requirements

- Schema validation.
- Invalid row links rejected.
- Deterministic plan generation.
- Roundtrip JSON/YAML.
- Markdown generation consistency.
- Status update tests.
- Agent-readable card output.
- Non-JS fixture.

### Docs/examples

- Plan concept.
- Card schema.
- Walkthrough schema.
- How plan links to matrix/showcase/evidence.
- Agent workflow guide.

### Definition of done

An agent can ask through CLI or MCP, “what should I do next for these rows?”, receive structured cards, execute them, and record evidence without relying on hidden repo knowledge.

---

## 3.9 Host applicability

### Public contract

Host applicability answers:

> “Can this use case/workflow run in this agent host, and what limitations apply?”

Host profile schema:

```yaml
schemaVersion: ucp/host-profile/v1
id: generic-mcp-stdio
title: Generic local MCP stdio host
capabilities:
  mcp:
    stdio: true
    tools: true
    resources: true
    prompts: true
    http: false
  filesystem:
    read: true
    write: true
  shell:
    execute: false
  network:
    outbound: unknown
limits:
  maxToolOutputBytes: 200000
```

Applicability result:

```json
{
  "schemaVersion": "ucp/host-applicability/v1",
  "hostId": "generic-mcp-stdio",
  "rowId": "showcase.cli-demo",
  "status": "applicable",
  "reasons": []
}
```

Statuses:

```text
applicable
degraded
not_applicable
unknown
```

### Generalisation bar

Do not hardcode one host as the product.

Ship these built-ins:

```text
generic-cli
generic-mcp-stdio
github-actions
```

Host-specific profiles for Claude Code, Cursor, VS Code, etc. can exist as versioned data profiles, but keep the **engine** generic.

### Test requirements

- Capability matching.
- Missing capability.
- Unknown host.
- Degraded host.
- Conflicting constraints.
- Profile schema validation.
- Host profile migration.
- MCP stdio host fixture.
- CLI-only fixture.

### Docs/examples

- Host applicability concept.
- Profile authoring.
- Built-in profiles.
- How to add a host.
- Difference between host capability and row requirement.

### Definition of done

A non-JS repo can run:

```bash
ucp host check generic-cli --json
ucp host check generic-mcp-stdio --json
```

…and get actionable applicability results for matrix rows, showcase specs, capsule generation, and plan workflows.

---

## 3.10 Evidence

### Public contract

Evidence records durable claims and artifacts that support rows, showcases, releases, or manual validation.

Commands:

```bash
ucp evidence record
ucp evidence status
ucp evidence void
```

Evidence event schema:

```json
{
  "schemaVersion": "ucp/evidence-event/v1",
  "eventId": "ev_abc123",
  "eventType": "record",
  "evidenceId": "evi_showcase_cli_first_fresh",
  "subject": {
    "rows": ["onboarding.first-fresh"],
    "showcaseRunId": "showcase_20260628_abc"
  },
  "artifact": {
    "kind": "transcript",
    "path": ".ucp/showcase/runs/.../transcript.md",
    "sha256": "..."
  },
  "producer": {
    "type": "ucp-showcase",
    "version": "1.0.0"
  },
  "createdAt": "2026-06-28T12:00:00.000Z"
}
```

Void event schema:

```json
{
  "schemaVersion": "ucp/evidence-event/v1",
  "eventType": "void",
  "evidenceId": "evi_showcase_cli_first_fresh",
  "reason": "Transcript contained unredacted secret-like test token",
  "voidedBy": "maintainer",
  "createdAt": "2026-06-28T13:00:00.000Z"
}
```

Evidence statuses:

```text
ACTIVE
VOID
MISSING_ARTIFACT
TAMPERED
SUPERSEDED
INVALID
```

### Generalisation bar

Evidence must support:

- local artifacts.
- external URIs.
- CI artifacts.
- showcase artifacts.
- manual records.
- screenshots or images as opaque artifacts.
- logs/transcripts.
- JSON reports.
- release attestations.
- docs-only evidence.

Evidence is not the same as proof. A manual evidence record must not make a row FRESH unless a policy explicitly treats it as a verifier input and it is proven.

### Test requirements

- Record.
- Status.
- Void.
- Void is append-only.
- Missing artifact.
- Tampered artifact.
- Duplicate evidence ID.
- Redaction.
- External evidence.
- Showcase-linked evidence.
- Release-gate evidence requirement.
- JSONL event log tamper tests.

### Docs/examples

- Evidence vs proof.
- Recording evidence.
- Voiding evidence.
- Artifact hashing.
- Privacy/redaction.
- Using evidence in release gates.

### Definition of done

A user can record, inspect, and void evidence without deleting history, and release gate can require active evidence for configured row kinds.

---

## 3.11 CLI

### Public contract

Full v1 CLI command tree:

```text
ucp init
ucp doctor
ucp validate
ucp schema list
ucp schema print <name>

ucp matrix check
ucp matrix normalize
ucp matrix list

ucp bind scan
ucp bind check
ucp bind add
ucp bind remove

ucp verify
ucp prove
ucp freshness
ucp status
ucp gate

ucp showcase list
ucp showcase run
ucp showcase status

ucp capsule generate
ucp capsule check

ucp plan generate
ucp plan check
ucp plan status

ucp host list
ucp host check

ucp evidence record
ucp evidence status
ucp evidence void
```

Global flags:

```text
--cwd <path>
--config <path>
--json
--format text|json
--no-color
--quiet
--verbose
--dry-run
--strict
```

Stable exit codes as above.

### Generalisation bar

CLI must work:

- from npm package install.
- from packed tarball.
- outside a pnpm monorepo.
- on a repo without Node project files.
- with Python/Go/docs fixtures.
- in non-TTY CI.
- from subdirectories.
- on Windows-style paths at least in path normalization tests.

### Test requirements

- Black-box CLI tests.
- JSON schema snapshot tests.
- Exit code tests.
- Help text smoke tests.
- No-color/non-TTY tests.
- Packed tarball install tests.
- Config discovery tests.
- Dirty worktree prove refusal.
- Unknown command suggestions.
- Error code stability tests.

### Docs/examples

- CLI quickstart.
- Full command reference.
- JSON output reference.
- Exit code reference.
- CI usage.
- Troubleshooting.

### Definition of done

Every public surface is reachable from the CLI, every mutating command supports `--dry-run` where meaningful, and every command has stable JSON output.

---

## 3.12 MCP server

### Public contract

The MCP server must expose the full surface, not just trust-core status.

Target current stable MCP spec line: `2025-11-25`.

Package:

```text
@use-cases-plugin/mcp
```

Binaries:

```text
ucp-mcp
use-cases-plugin-mcp
```

### Tools

Use stable names:

```text
ucm_init
ucm_doctor
ucm_validate

ucm_matrix_check
ucm_matrix_list

ucm_bind_scan
ucm_bind_check
ucm_bind_add

ucm_verify
ucm_prove
ucm_freshness
ucm_status
ucm_gate

ucm_showcase_list
ucm_showcase_run
ucm_showcase_status

ucm_capsule_generate
ucm_capsule_check

ucm_plan_generate
ucm_plan_check
ucm_plan_status

ucm_host_list
ucm_host_check

ucm_evidence_record
ucm_evidence_status
ucm_evidence_void

ucm_schema_list
ucm_schema_get
```

### Resources

```text
ucp://matrix
ucp://config
ucp://bindings
ucp://freshness
ucp://gate
ucp://ledger
ucp://evidence
ucp://showcase/runs
ucp://capsules
ucp://plans
ucp://host/profiles
ucp://schemas/<name>
```

### Prompts

```text
ucp/adopt-repo
ucp/bind-row
ucp/recover-suspect-row
ucp/release-review
ucp/write-showcase
ucp/record-evidence
```

### Security bar

The MCP server must not expose a generic `run_shell` tool.

Mutating tools require explicit structured intent:

```json
{
  "dryRun": true,
  "confirm": false
}
```

For dangerous operations such as `prove`, require server config:

```yaml
mcp:
  allowProve: false
  allowMutations: true
  allowedRoots:
    - "."
```

Hard requirements:

- validate all tool inputs.
- reject unknown fields if schema says strict.
- sanitize outputs.
- redact secrets.
- rate-limit expensive calls.
- timeout long-running operations.
- never execute commands outside configured verifiers/showcases.
- no shell interpolation by default.
- lock workspace root.
- deny symlink escape.
- return stable structured errors.

These align with MCP’s current tool security guidance around validation, access controls, rate limits, and output sanitization. citeturn944347view3

### Transport decision

For v1:

- ship **stdio local MCP** as stable.
- do **not** ship remote HTTP MCP as stable unless OAuth 2.1/protected resource metadata/PKCE/security docs are fully implemented. The current MCP authorization spec makes remote/HTTP authorization non-trivial. citeturn944347view5

### Registry readiness

Publish to npm first. Then publish MCP metadata with `server.json` and matching `mcpName` once the server package is public. Treat official registry publication as a discoverability step, not as the source of truth, because the MCP Registry is still marked preview. citeturn396727view0turn396727view3

### Test requirements

- MCP protocol smoke tests with SDK client.
- Tool list snapshot.
- Resource list snapshot.
- Prompt list snapshot.
- Input validation failure tests.
- Mutation disabled tests.
- Prove disabled tests.
- Rate limit/timeout tests.
- Redaction tests.
- Non-JS fixture through MCP.
- Packed package launch test.
- MCP Inspector/manual smoke in release checklist.

### Docs/examples

- MCP install.
- MCP client config examples.
- Tool reference.
- Resource reference.
- Prompt reference.
- Security model.
- Mutating tool controls.
- Prove-through-MCP warning.

### Definition of done

An agent can use only MCP tools/resources/prompts to initialize a repo, inspect matrix/freshness, bind rows, run verify, generate capsule/plan, check host applicability, record evidence, run showcase, and run release gate. `prove` may be exposed but disabled by default.

---

# 4. Cross-cutting public v1 work

## 4.1 Schema stability

Every persisted or public machine-readable object needs a schema:

```text
matrix.schema.json
config.schema.json
binding.schema.json
ledger.schema.json
proof.schema.json
freshness.schema.json
gate.schema.json
showcase-spec.schema.json
showcase-run.schema.json
capsule.schema.json
plan.schema.json
host-profile.schema.json
host-applicability.schema.json
evidence-event.schema.json
cli-envelope.schema.json
mcp-tool-results.schema.json
```

Rules:

- all schemas versioned under `v1`.
- every object has `schemaVersion`.
- every schema has examples.
- every CLI/MCP JSON result validates against schema in tests.
- schema changes are SemVer-governed.
- v1 readers reject unknown major schema versions.
- v1 readers tolerate unknown optional fields only where documented.

## 4.2 TypeScript API stability

Public exports from `@use-cases-plugin/core` must be deliberate.

Recommended public API groups:

```ts
export * from "./schemas";
export * from "./matrix";
export * from "./bindings";
export * from "./verify";
export * from "./prove";
export * from "./freshness";
export * from "./gate";
export * from "./evidence";
export * from "./showcase";
export * from "./capsule";
export * from "./plan";
export * from "./host";
export * from "./errors";
```

Do not export internal filesystem helpers casually. Once public at `1.0.0`, they carry SemVer weight.

## 4.3 CLI JSON stability

Treat these as public API:

- command names.
- flags.
- JSON envelope.
- `data` shape.
- error codes.
- exit codes.
- config discovery behavior.
- default paths.

Human text can evolve in minor/patch releases. JSON cannot break without a major.

## 4.4 MCP stability

Treat these as public API:

- tool names.
- resource URI patterns.
- prompt names.
- input schemas.
- structured output schemas.
- error codes.
- default safety policy.

Adding a new optional tool is minor. Renaming/removing/changing input semantics is major.

## 4.5 Threat model

Publish a real `SECURITY.md` and `docs/security/threat-model.md`.

Assets:

- signing private key.
- proof ledger.
- matrix rows.
- bindings.
- verifier definitions.
- showcase transcripts.
- evidence artifacts.
- release workflow.
- npm package.
- MCP server execution boundary.

Threats:

- forged proof.
- replayed proof.
- stale proof accepted as fresh.
- ledger truncation.
- ledger reordering.
- malicious verifier command.
- command injection.
- compromised CI secret.
- untrusted PR accessing prove key.
- package tarball includes secrets.
- MCP tool prompt injection.
- arbitrary shell execution through MCP.
- malicious showcase transcript.
- evidence artifact tampering.
- path traversal/symlink escape.
- dependency compromise.
- maintainer accidentally publishing wrong package contents.

Minimum mitigations:

- ed25519 signatures.
- hash-chained ledger.
- keyring/revocation.
- protected prove job.
- command argv arrays.
- env allowlists.
- no prove on PRs.
- package content allowlist.
- tarball scans.
- MCP input validation and no generic shell tool.
- transcript redaction.
- evidence hashing.
- CI attestations.
- documented limitations.

## 4.6 Signing-key story

Public v1 needs a real key lifecycle.

Commands:

```bash
ucp key generate
ucp key inspect
ucp key export-public
ucp key rotate
ucp key revoke
```

If you do not want these as public CLI commands, at least ship documented scripts and stable keyring schema.

Keyring schema:

```yaml
schemaVersion: ucp/keyring/v1
keys:
  - keyId: release-2026-q3
    algorithm: ed25519
    publicKey: base64...
    validFrom: 2026-06-01T00:00:00.000Z
    validUntil: null
    status: active
```

Private key handling:

- never commit private key.
- CI secret only.
- protected environment only.
- rotation documented.
- revocation documented.
- lost key recovery documented.
- test key clearly marked and blocked from release policy.

## 4.7 Prove-job hardening

Recommended GitHub Actions structure:

```text
PR:
  validate
  test
  ucp verify
  ucp gate --allow-unproven? no key

main after merge:
  validate
  test
  ucp verify
  ucp prove
  commit/open PR with ledger update

release tag:
  validate
  test
  ucp gate
  pack
  attest
  publish
```

Important design point: if proof persists back to repo, the proof entry usually proves the **subject commit** and is committed in a later **ledger commit**. Model this explicitly:

```json
{
  "subjectGitCommit": "code-and-matrix-commit",
  "ledgerGitCommit": "commit-that-added-proof"
}
```

Otherwise you will get confusing self-referential proof behavior.

## 4.8 Supply-chain release hardening

Minimum v1 release hardening:

- npm Trusted Publishing, not long-lived npm publish token.
- publish from supported cloud CI.
- package provenance enabled.
- `id-token: write` only where required.
- npm package `repository` metadata correct.
- `files` allowlist in every package.
- `npm pack --dry-run` or `pnpm pack` manifest review.
- tarball contents checked in CI.
- no `.env`, private keys, fixtures with secrets, local ledger keys, or raw transcripts with secrets in tarballs.
- lockfile committed.
- dependency review.
- OpenSSF Scorecard workflow or equivalent security checklist. OpenSSF describes Scorecard as automated checks for open-source security risk assessment. citeturn396727view7
- release artifacts attested. GitHub artifact attestations are suitable for producing signed build provenance claims. citeturn944347view6
- SBOM generated for release artifacts.
- changelog generated.
- release tag signed if your org supports it.
- dry-run install from packed tarballs in clean fixtures.

## 4.9 Ledger integrity hardening

Current “append-only ledger” is not enough unless it is hash-chained and externally anchored.

Public v1 minimum:

- hash chain.
- signed entries.
- signed checkpoints.
- release checkpoint file.
- checkpoint verified by release gate.
- ledger verification command:

```bash
ucp ledger verify --json
```

- ledger doctor command:

```bash
ucp doctor --ledger
```

Do not let the product imply impossible guarantees. The honest claim is:

> UCM makes proof history tamper-evident inside the repository and strengthens that with protected CI, signed checkpoints, and release attestations.

## 4.10 Onboarding and time-to-first-FRESH

This is a release-critical surface.

Target path:

```bash
npm install -D @use-cases-plugin/cli
npx ucp init
npx ucp matrix check
npx ucp bind scan
npx ucp verify
npx ucp prove --local-test-key
npx ucp freshness
```

For real CI:

```bash
ucp key generate
ucp key export-public
# store private key in CI secret
ucp init ci github-actions
```

`ucp init` should detect, but not assume:

- npm.
- pnpm.
- yarn.
- bun.
- pytest.
- go test.
- cargo test.
- make.
- no test runner.

Detection should produce suggested config, not hidden behavior.

## 4.11 Public docs stack

Required docs:

```text
README.md
docs/getting-started.md
docs/concepts/matrix.md
docs/concepts/bindings.md
docs/concepts/freshness.md
docs/concepts/proofs-ledger.md
docs/concepts/evidence.md
docs/concepts/showcase.md
docs/concepts/capsule.md
docs/concepts/plan.md
docs/concepts/host-applicability.md

docs/reference/config.md
docs/reference/schemas.md
docs/reference/cli.md
docs/reference/mcp.md
docs/reference/error-codes.md
docs/reference/exit-codes.md

docs/security/threat-model.md
docs/security/key-management.md
docs/security/ci-hardening.md
docs/security/mcp-security.md
docs/security/supply-chain.md

docs/tutorials/first-fresh-row.md
docs/tutorials/github-actions.md
docs/tutorials/ci-neutral.md
docs/tutorials/python-pytest.md
docs/tutorials/go-test.md
docs/tutorials/docs-only.md
docs/tutorials/showcase-run.md
docs/tutorials/mcp-server.md

docs/release/public-v1-checklist.md
docs/release/publishing.md
docs/migration/pre-v1-rename.md
```

## 4.12 Examples

Required examples:

```text
examples/js-vitest
examples/js-npm-test
examples/python-pytest
examples/go-test
examples/docs-only
examples/mcp-client
examples/showcase
examples/ci-neutral
```

Each example must be tested from packed tarballs, not workspace imports.

Acceptance command:

```bash
pnpm build
pnpm pack:all
./scripts/test-packed-example examples/python-pytest
./scripts/test-packed-example examples/go-test
./scripts/test-packed-example examples/docs-only
```

## 4.13 Governance files

Minimum public repo files:

```text
LICENSE
README.md
CHANGELOG.md
CODE_OF_CONDUCT.md
CONTRIBUTING.md
SECURITY.md
SUPPORT.md
GOVERNANCE.md
NOTICE
```

Also add:

```text
.github/ISSUE_TEMPLATE/bug.yml
.github/ISSUE_TEMPLATE/feature.yml
.github/pull_request_template.md
.github/dependabot.yml
.github/workflows/ci.yml
.github/workflows/release.yml
.github/workflows/scorecard.yml
```

## 4.14 Versioning and release process

Use SemVer strictly.

Pre-1.0 internal versions do not matter. Public release should go:

```text
1.0.0-rc.1
1.0.0-rc.2 if needed
1.0.0
```

Public compatibility policy:

- Patch: bug fixes only, no schema/CLI/MCP breaking changes.
- Minor: additive fields, new commands/tools, new optional schema fields.
- Major: remove/rename/change semantics.

Publish all three packages together for v1:

```text
@use-cases-plugin/core@1.0.0
@use-cases-plugin/cli@1.0.0
@use-cases-plugin/mcp@1.0.0
```

---

# 5. Generality minimum bar

## Verifier model

The verifier model must become:

```text
generic command verifier + optional presets
```

Not:

```text
pnpm/vitest verifier with some hooks
```

Required built-in presets:

```text
command.generic
js.npm-test
js.pnpm-test
js.vitest
python.pytest
go.test
rust.cargo-test
make.target
```

But all presets compile down to the same generic verifier schema.

## CI model

GitHub Actions can be best-documented, but the core proof schema must be CI-neutral.

Required support:

```text
github-actions adapter
generic authority file
local authority for development only
```

Optional but good:

```text
gitlab-ci adapter
circleci adapter
```

## Showcase generality

Showcase specs must use runner adapters, not hardcoded repo scripts.

No direct assumptions about:

- Node.
- package manager.
- browser.
- LLM provider.
- network.
- GitHub.

## Capsule generality

Capsule must summarize UCM state, not TypeScript project state.

Bad:

```text
“package scripts”
“vitest coverage”
“pnpm workspace”
```

Good:

```text
“configured verifiers”
“release-required rows”
“freshness status”
“evidence artifacts”
“host applicability”
```

## Plan generality

Plan cards must be repo/workflow-neutral.

A card should say:

```text
Run verifier core-tests
```

not:

```text
Run pnpm vitest
```

unless the repo config explicitly defines that verifier that way.

## Host applicability generality

Host profiles are data. The engine is generic.

Do not build host applicability around one preferred client.

## Evidence generality

Evidence artifacts are opaque typed blobs with hashes. Do not assume GitHub artifact URLs, screenshots, JS logs, or one transcript format.

---

# 6. Sequenced roadmap

## Critical path

The true dependency chain is:

```text
Naming/package rename
  → public schema/versioning envelope
  → verifier generalisation
  → ledger hardening/keyring
  → freshness semantics
  → release gate
  → CLI/MCP contract freeze
  → lifecycle surfaces hardening
  → examples/docs/dogfood
  → supply-chain release
  → rc
  → public 1.0.0
```

Everything else parallelizes around that.

---

## Phase 0 — scope freeze and contract design

### Workstream A: Naming and packaging

Deliverables:

- package scope decision committed.
- package names changed.
- CLI bins changed.
- MCP bins changed.
- old names removed from code except migration note.
- npm org/scope reserved.

Acceptance:

```bash
rg "presentation-skills|use-cases-plugin" .
```

Only migration docs may match.

### Workstream B: Public contract RFC

Deliverables:

- schema list finalized.
- CLI command tree finalized.
- MCP tools/resources/prompts finalized.
- public TypeScript exports finalized.
- SemVer policy written.
- error code system designed.

Acceptance:

- every public surface has a schema or documented contract.
- every schema has an owner and test plan.
- no “builder-grade” undocumented object remains.

---

## Phase 1 — schema and API foundation

### Workstream C: Schema package foundation

Deliverables:

- JSON Schemas.
- TypeScript types generated or co-authored.
- schema validation utilities.
- canonical JSON hashing utilities.
- JSON output envelope.

Acceptance:

- schemas validate examples.
- invalid fixtures fail with stable errors.
- CLI/MCP use the same core result envelope.

### Workstream D: Error and diagnostic system

Deliverables:

- `UCP_*` error code registry.
- diagnostics formatter.
- JSON diagnostics.
- docs page generated from registry.

Acceptance:

- no raw thrown errors reach CLI/MCP.
- snapshot tests for error outputs.

---

## Phase 2 — trust core hardening

### Workstream E: Verifier generalisation

Deliverables:

- generic command verifier.
- verifier presets.
- CI-neutral authority schema.
- GitHub adapter.
- local dev authority.
- verifier docs.

Acceptance:

- Python/Go/docs fixtures verify.
- pnpm/vitest is only a preset.
- shell injection tests pass.

### Workstream F: Ledger and keyring hardening

Deliverables:

- hash-chained ledger.
- signed entries.
- keyring.
- key rotation/revocation.
- checkpoint support.
- ledger verify command.

Acceptance:

- tamper/reorder/truncate tests pass.
- old unchained ledger migration tested if needed.
- release gate refuses invalid ledger.

### Workstream G: Freshness

Deliverables:

- formal status derivation.
- reason codes.
- per-row derivation graph.
- JSON output.
- docs.

Acceptance:

- full transition matrix tested.
- every non-FRESH result gives a fix path.

### Workstream H: Release gate

Deliverables:

- release policy schema.
- gate evaluator.
- exit codes.
- JSON output.
- CI annotations optional.
- waiver policy if included.

Acceptance:

- own repo cannot pass release gate with unproven required rows.
- required rows must be FRESH.

---

## Phase 3 — lifecycle surface hardening

These can parallelize once schemas are stable.

### Workstream I: Evidence

Deliverables:

- evidence event log.
- record/status/void.
- artifact hashing.
- evidence linkage.
- release gate integration.
- docs.

Acceptance:

- void is append-only.
- tampered artifacts detected.
- showcase can create evidence.

### Workstream J: Showcase

Deliverables:

- showcase spec schema.
- runner abstraction.
- fake deterministic agent.
- MCP/local runner.
- artifact capture.
- transcript redaction.
- status reporting.
- evidence integration.

Acceptance:

- showcase passes in at least one clean example.
- failed showcase produces useful evidence/status.
- no secrets in artifacts.

### Workstream K: Capsule

Deliverables:

- capsule JSON/Markdown generation.
- size budget.
- staleness hash.
- row/evidence/freshness links.
- docs.

Acceptance:

- deterministic output.
- non-JS fixture capsule works.
- stale capsule detected.

### Workstream L: Plan

Deliverables:

- plan schema.
- cards.
- walkthrough.
- linked rows/showcases/evidence.
- generated Markdown.
- MCP prompt integration.

Acceptance:

- invalid row links rejected.
- agents can consume plan cards through CLI and MCP.

### Workstream M: Host applicability

Deliverables:

- host profile schema.
- capability matcher.
- built-in generic profiles.
- applicability result schema.
- docs.

Acceptance:

- generic CLI and MCP stdio profiles work.
- unknown/degraded/not-applicable cases tested.

---

## Phase 4 — full CLI and MCP surface

### Workstream N: CLI completion

Deliverables:

- full command tree.
- global flags.
- JSON mode.
- exit codes.
- help text.
- tarball install tests.

Acceptance:

- every core surface reachable by CLI.
- every command has `--json`.
- packed tarball examples pass.

### Workstream O: MCP completion

Deliverables:

- tool/resource/prompt list.
- input schemas.
- output schemas.
- safe mutation config.
- stdio server.
- docs.
- registry metadata.

Acceptance:

- MCP client contract tests pass.
- mutating tools can be disabled.
- `prove` disabled by default.
- no arbitrary shell tool.
- package can launch via `npx @use-cases-plugin/mcp`.

---

## Phase 5 — dogfood and adoption

### Workstream P: Own-repo matrix adoption

Current state is 1 of 82 rows bound. That is not compatible with public v1.

Process:

1. Normalize the 82 rows.
2. Delete duplicates and stale builder notes.
3. Convert future/non-v1 ideas into docs or issues, not matrix claims.
4. Mark every shipped public behavior row `required_for_release: true`.
5. Bind every surviving v1 row.
6. Configure verifiers for every required row.
7. Prove every required row.
8. Make release gate enforce them.

Acceptance:

- no shipped surface has unbound required rows.
- every CLI command has at least one required row.
- every MCP tool/resource/prompt group has required rows.
- every lifecycle surface has showcase/evidence/docs rows.
- `ucp gate` passes only after proof ledger is current.

### Workstream Q: Examples

Deliverables:

- JS, Python, Go, docs-only, MCP examples.
- each installs from packed tarball.
- each has first-FRESH tutorial.
- each has release gate example.

Acceptance:

- CI runs all examples from tarballs.
- no workspace linking.

### Workstream R: Docs

Deliverables:

- full docs stack above.
- generated CLI reference.
- generated schema reference.
- generated MCP reference.
- threat model.
- public v1 checklist.

Acceptance:

- docs examples are tested.
- docs do not mention obsolete names.
- every error code links to docs.

---

## Phase 6 — supply-chain and release

### Workstream S: Release engineering

Deliverables:

- Trusted Publishing.
- provenance.
- artifact attestations.
- tarball content check.
- SBOM.
- changelog.
- signed tag/checkpoint.
- release workflow.

Acceptance:

- `1.0.0-rc.1` published from CI.
- provenance visible.
- package install works.
- MCP package launches.
- registry metadata prepared or published.

### Workstream T: Security review

Deliverables:

- threat model reviewed.
- MCP security reviewed.
- key handling reviewed.
- tarball reviewed.
- dependency review.
- path traversal/symlink tests.
- command injection tests.
- redaction tests.

Acceptance:

- no P0/P1 security findings open.
- no “known shaky” surface hidden by docs language.

---

# 7. Full-release definition-of-done checklist

## Product contracts

- [ ] Product name is `Use Cases Plugin`.
- [ ] NPM scope is `@use-cases-plugin`.
- [ ] Packages are `core`, `cli`, `mcp`.
- [ ] CLI binary `ucp` works.
- [ ] MCP binary `ucp-mcp` works.
- [ ] All public schemas are versioned.
- [ ] All public JSON outputs validate.
- [ ] All public error codes documented.
- [ ] SemVer policy written.

## Matrix/bindings/trust

- [ ] Matrix schema stable.
- [ ] Binding marker grammar stable.
- [ ] Bindings work across multiple languages.
- [ ] Verifier model is generic.
- [ ] pnpm/vitest is only a preset.
- [ ] ed25519 proof entries validate.
- [ ] Ledger is hash-chained.
- [ ] Keyring supports rotation/revocation.
- [ ] Freshness derivation is deterministic.
- [ ] Release gate enforces required rows.

## Lifecycle surfaces

- [ ] Showcase spec/run schemas stable.
- [ ] Showcase runs produce evidence.
- [ ] Capsule JSON/Markdown stable.
- [ ] Plan cards/walkthrough stable.
- [ ] Host profiles/applicability stable.
- [ ] Evidence record/status/void stable.
- [ ] All lifecycle surfaces reachable through CLI.
- [ ] All lifecycle surfaces reachable through MCP.

## CLI

- [ ] Every command has `--json`.
- [ ] Exit codes stable.
- [ ] Non-TTY behavior tested.
- [ ] Packed tarball install tested.
- [ ] Help/reference generated.

## MCP

- [ ] Tools/resources/prompts stable.
- [ ] Inputs validated.
- [ ] Outputs sanitized.
- [ ] Mutations configurable.
- [ ] `prove` disabled by default.
- [ ] No generic shell execution tool.
- [ ] stdio local transport documented.
- [ ] MCP registry metadata prepared.

## Generality

- [ ] JS example passes.
- [ ] Python example passes.
- [ ] Go example passes.
- [ ] docs-only example passes.
- [ ] CI-neutral proof authority works.
- [ ] GitHub Actions adapter works.
- [ ] No hidden dependency on pnpm/vitest.
- [ ] No hidden dependency on this repo.

## Security

- [ ] Threat model published.
- [ ] Key management docs published.
- [ ] CI hardening docs published.
- [ ] Supply-chain docs published.
- [ ] MCP security docs published.
- [ ] Command injection tests pass.
- [ ] Path traversal tests pass.
- [ ] Symlink escape tests pass.
- [ ] Redaction tests pass.
- [ ] Package tarball scan passes.

## Supply chain

- [ ] Trusted Publishing configured.
- [ ] Provenance enabled.
- [ ] Artifact attestations generated.
- [ ] SBOM generated.
- [ ] Package contents reviewed.
- [ ] Changelog generated.
- [ ] Release tag/checkpoint created.
- [ ] `npm pack` output verified.

## Own-repo dogfood

- [ ] 82-row matrix triaged.
- [ ] Every surviving v1 row bound or explicitly non-bindable by schema.
- [ ] Every shipped public surface has required rows.
- [ ] Every required row is FRESH.
- [ ] Release gate passes on the repo.
- [ ] Showcase demonstrates public workflows.
- [ ] Capsule/plan/host/evidence all used in the repo itself.

## Release

- [ ] `1.0.0-rc.1` published.
- [ ] RC installed in fresh repos.
- [ ] RC examples pass from npm or packed tarballs.
- [ ] No P0/P1 bugs open.
- [ ] Public `1.0.0` published for all packages together.
- [ ] Post-publish smoke:
  - [ ] `npx ucp --help`
  - [ ] `npx ucp init`
  - [ ] `npx ucp-mcp` launches
  - [ ] docs links valid
  - [ ] provenance/attestation visible
  - [ ] MCP metadata valid

---

# 8. The hard advice

The biggest risk is not writing more code. It is **shipping accidental contracts**.

For public v1, every builder-grade shortcut becomes a support burden:

- A pnpm/vitest default becomes “UCM only works for TS monorepos.”
- A loose ledger becomes “append-only” marketing that is not true.
- A generic MCP shell wrapper becomes a security liability.
- A showcase that only works in your repo becomes a demo script, not a public surface.
- A matrix with 82 mostly-unbound rows tells users the tool cannot dogfood itself.

The right execution posture is contract-first:

1. Rename now.
2. Freeze schemas.
3. Generalize verifiers.
4. Harden ledger/keyring.
5. Make freshness/release gate uncompromising.
6. Bring every lifecycle surface up to the same schema/test/doc standard.
7. Expose everything through CLI and MCP.
8. Prove it on your own repo and clean non-JS fixtures.
9. Publish only after packed-tarball installs pass.

That is the no-corners version.