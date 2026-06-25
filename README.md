# Presentation Skills

Presentation Skills gives agents a living use-case matrix, append-only proof
history, and live showcase runs. It replaces static `TEST-MATRIX.md` files with
behavior rows that can be planned up front, updated during work, and used for a
final user-visible demo when that is valuable.

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
presentation-skills matrix validate --repo . --json
presentation-skills evidence record --repo . --use-case matrix.core.validate --kind test_result --result pass --json
presentation-skills plan showcase --repo . --max-items 3 --json
presentation-skills showcase start --repo . --adhoc --select matrix.core.validate --json
presentation-skills host conformance --all --repo . --json
presentation-skills doctor package --json
```

MCP tools wrap the same CLI envelopes. Host projections are thin activation
stubs for Claude, Codex, Copilot, and OpenCode; they are not proof of live host
support by themselves.
