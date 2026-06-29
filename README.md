# Use Case Matrix (UCM)

Use Case Matrix keeps an agent's product claims honest. It gives a repo a living
use-case matrix, binds each row to the code that satisfies it, and marks a row
**FRESH** only when trusted CI has signed proof that the current code, binding,
and verifier context still match — so stale claims become visible instead of
silently trusted. On top of that trust core it adds plans, capsules, host
applicability, evidence, and live showcase runs, replacing static
`TEST-MATRIX.md` files with behaviour rows that are planned up front, updated
during work, proven in CI, and demonstrated when that is valuable.

> Installs as `@use-case-matrix/cli` (binary `ucm`) plus an MCP server
> (`@use-case-matrix/mcp`, binary `ucm-mcp`) that agents drive directly.

New here? Start with [the documentation index](docs/README.md) and the
[getting-started tutorial](docs/getting-started.md).

## Workflows

- continuous: recommended default. Add or adjust use cases during planning,
  record evidence as work lands, and finish with a focused showcase when the
  work needs visible proof.
- backfill: migrate old `TEST-MATRIX.md` rows into draft use cases, then review
  and activate the useful rows.
- showcase-only: select a few high-value use cases and run a live demo without
  adopting the full lifecycle.
- audit-only: load and validate the matrix, evidence, and histories to inspect
  current project risk.
- migration: run the TEST-MATRIX importer in dry-run first, then write draft
  use-case YAML only when the report looks right.

## Main Commands

```bash
ucm matrix validate --repo . --json
ucm evidence record --repo . --use-case matrix.core.validate --kind test_result --result pass --json
ucm plan showcase --repo . --max-items 3 --json
ucm showcase start --repo . --adhoc --select matrix.core.validate --json
ucm host conformance --all --repo . --json
ucm doctor package --json
```

MCP tools wrap the same CLI envelopes. Host projections are thin activation
stubs for Claude, Codex, Copilot, and OpenCode; they are not proof of live host
support by themselves.

## Use-case markers: precommit + CI

The use-case-markers guard (spec `docs/superpowers/specs/2026-06-28-use-case-markers-v1.md`)
is wired into both a local precommit hook and CI:

- Precommit (ergonomics, not authority): `scripts/use-cases-precommit.sh` runs
  `validate-ledger --staged` and `scan --policy-mode feature`. It BLOCKS the
  commit on integrity failures (malformed/duplicate/unregistered markers,
  non-append ledger or registry edits, invalid proof schema/signature, registry
  conflict) and prints a loud, non-blocking warning for SUSPECT / UNPROVEN /
  UNBOUND rows. It is not installed automatically; enable it with:

  ```bash
  ln -s ../../scripts/use-cases-precommit.sh .git/hooks/pre-commit
  ```

- CI (authority): `.github/workflows/use-cases.yml` runs `validate-ledger`
  (blocks on failure), `scan` (feature blocks INVALID only; release also blocks
  required rows that are not FRESH, and prints inferred Swift spans), and an
  optional `prove` job that mints signed proof events on the release branch from
  the `UCM_CI_SIGNING_KEY` secret. The policy mode is selected from the branch
  (release on `main` / `release/**`, feature elsewhere) or a manual input.
