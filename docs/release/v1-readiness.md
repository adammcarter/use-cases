# Public v1 Readiness Status

Snapshot of where Use Cases Plugin stands against the public-v1 program in
[`public-v1-roadmap.md`](./public-v1-roadmap.md). The engineering work is
**complete and on `main`**; the only remaining step is the owner-only npm
publish setup (you cannot grant an agent npm publish rights).

## Done (on `main`, CI green)

| Area | Status |
|---|---|
| **Identity** | Renamed to Use Cases Plugin — `@use-cases-plugin/{core,cli,mcp}`, CLI `ucp`, MCP `ucp-mcp`, schema `$id`s on `use-cases-plugin.dev` |
| **Contract** | Public API + SemVer declared ([stability.md](../reference/stability.md)); every persisted object is schema-versioned; `UCP_*` error-code registry; a conformance test asserts every CLI `--json` output validates |
| **Trust core** | Generic command verifiers + language presets (no pnpm/vitest assumption); tamper-evident hash-chained ledger (reorder/edit/truncate caught, CI-gated); keyring with rotation/revocation + validity windows (fail-closed); CI-neutral authority (GitHub/GitLab/CircleCI or `--authority-file`) |
| **Release gate** | `required_for_release` rows enforced **after** prove in CI (no bootstrap deadlock); 3 of our own rows are gated and FRESH on `main` |
| **Security** | Path-traversal closed (id-pattern + symlink-safe containment); consistent secret redaction; `prove`/shell never exposed over MCP; honest [SECURITY.md](../../SECURITY.md) threat model |
| **Surfaces** | `ucp init` (templated onboarding); MCP **resources + prompts** (read-only); evidence/showcase/capsule/plan/host all schema-backed + conformance-tested |
| **Adoptability** | A real **non-JS (Python) example** goes bind → verify (`pytest`) → prove → **FRESH** from the **packed npm tarball** (`examples/python-pytest`); markers work in `#`/`//`/etc. comment styles |
| **Docs** | Getting-started, concepts, verifier/CI/security guides, per-language tutorial, docs index |
| **Packaging** | Clean tarballs (validated — no `src`/tests/secrets); `publishConfig` public + provenance; tokenless Trusted-Publishing release workflow; `docs/release/publishing.md` runbook |
| **Governance** | LICENSE (MIT), CONTRIBUTING, CODE_OF_CONDUCT, SUPPORT, issue/PR templates, dependabot, CHANGELOG |
| **Dogfood** | 7 rows bound to real code with genuine acceptance tests, all FRESH on `main` via the real CI key |

## Documented v1 boundaries (deliberate, not gaps)

- Host profiles are the four built-ins; custom hosts are post-v1 (trust core is host-independent).
- The five trust-engine commands always emit JSON (machine/CI-oriented).
- GitHub Actions is the first-class CI; other providers via the documented CI-neutral authority contract.
- Local stdio MCP only (remote/HTTP transport is post-v1).

## Remaining — owner-only

These require your accounts and cannot be done by an agent (see
[publishing.md](./publishing.md) for the full runbook):

1. Reserve the **`@use-cases-plugin` npm scope**.
2. Configure a **Trusted Publisher** on each of the three packages (GitHub Actions, repo `adammcarter/use-cases-plugin`, workflow `release.yml`).
3. Set versions (`1.0.0-rc.1` → smoke-test from npm → `1.0.0`), tag `vX.Y.Z` — the release workflow then publishes with provenance.

After step 3, v1 is published. No code work remains.
