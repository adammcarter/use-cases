# Contributing to Use Cases Plugin

Thanks for helping improve Use Cases Plugin (UCM). This guide covers local setup,
the repo layout, the trust model you should keep in mind, and what we expect on
a pull request.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
Security issues go through private advisories — see [SECURITY.md](SECURITY.md),
never a public issue.

## Development setup

UCM is a pnpm-managed TypeScript monorepo. You need Node (active LTS) and
Corepack (bundled with Node) to pin pnpm.

```bash
corepack pnpm install      # install workspace dependencies
corepack pnpm -s build     # build all three packages (tsc -b + schema copy)
corepack pnpm -s test      # run the full vitest suite
```

Useful extras:

```bash
corepack pnpm -s typecheck             # tsc -b, no emit
corepack pnpm cli -- matrix validate --repo . --json   # run the built CLI
```

## Monorepo layout

| Path | Package | What it is |
|---|---|---|
| `packages/core` | `@use-cases-plugin/core` | Core domain library: matrix, bindings, verify/prove, freshness, ledger, evidence, showcase, capsule, plan, host. The schemas live under `schemas/v1`. |
| `packages/cli` | `@use-cases-plugin/cli` | The `ucp` CLI (alias `use-cases-plugin`). Thin command layer over core; owns the `--json` envelopes and exit codes. |
| `packages/mcp` | `@use-cases-plugin/mcp` | The `ucp-mcp` MCP server. Wraps the same envelopes for agents over local stdio. |
| `docs/` | — | Reference, security, and release docs. `docs/reference/stability.md` is the SemVer contract. |
| `tests/` | — | Cross-package and acceptance tests. |

The three packages release **together at the same version**.

## The trust model in one paragraph

A row is **FRESH** only when a valid ed25519 signature from a configured trusted
authority covers proof that the current row, binding, span, and verifier context
all still match. **CI is the authority**: the private signing key lives only as
a CI secret. `verify` runs anywhere with no key and never writes; `prove` holds
the key, signs a successful verification, and appends it to the tamper-evident
hash-chained ledger — so contributors and PRs can `verify` freely but cannot
mint FRESH locally. Keep this split intact: do not add a path that lets `prove`
run without the trusted key, and do not expose `prove` or a generic shell over
MCP.

## Making changes

- **Behavioural changes need tests.** Any change to logic/behaviour must add or
  update tests in the same PR, and the full suite must stay green. Prose, docs,
  config, and schema-example edits do not need a failing test first.
- **Respect the public contract.** CLI command/flag names, `--json` output
  shapes, exit codes, MCP tool names + schemas, persisted file formats, and the
  documented `@use-cases-plugin/core` exports are versioned per
  [`docs/reference/stability.md`](docs/reference/stability.md). If your change is
  additive it's a **minor**; if it removes/renames/repurposes a contract or
  changes an output shape it's a **major** — call that out in the PR.
- **Keep it generic.** UCM is language/CI-neutral. Don't bake in a hidden
  dependency on pnpm/vitest or GitHub Actions; `pnpm`/`vitest` is one verifier
  preset, not an assumption.

## Pull request expectations

- **Green CI.** `corepack pnpm -s build` and `corepack pnpm -s test` must pass.
- **Conventional-ish commits.** Use clear, imperative, prefixed messages
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`). One logical change
  per commit.
- **SemVer impact noted.** State whether the change is patch / minor / major per
  the stability policy, and add a `CHANGELOG.md` entry under `## [Unreleased]`.
- **Docs updated.** If you change a contract or behaviour, update the relevant
  doc in the same PR.
- **Tests included** for behavioural changes, as above.

Open a draft PR early if you'd like feedback on direction before polishing.
