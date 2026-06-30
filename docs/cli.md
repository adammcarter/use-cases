# CLI Reference

All commands use JSON envelopes with `schema_version`, `protocol_version`,
`command`, `ok`, `complete`, `data`, `diagnostics`, and `context`.

## Onboarding

- `ucp init [--repo <dir>] [--template generic|js-vitest|python-pytest|go-test] [--component <id>] [--force] [--json]`:
  scaffold a minimal working workspace — a `use-cases-plugin.yml` (with a
  `verifiers.default` matching the template) and a `use-cases/example.yml` whose
  one row already validates. The scaffolded workspace passes `matrix validate`
  immediately. `init` never generates or writes a private key and never creates
  the GitHub workflow; it prints the next steps (key setup, CI workflow) instead.
  It refuses to overwrite an existing `use-cases-plugin.yml` unless `--force`
  is given. Omit `--json` for a human-readable summary.

## Matrix

- `matrix validate --repo <path> --json`: load all sharded YAML use cases and
  report structural integrity.
- `matrix list --repo <path> --json`: list addressable use cases. Filters:
  `--value`, `--journey-role`, `--lifecycle`, `--host`, `--tag`,
  `--changed-path`.
- `matrix status --repo <path> --json`: combine matrix integrity and evidence
  replay status.
- `matrix upsert --repo <path> --file <path> (--use-case-json <json> | --use-case-file <path>) --json`:
  add or update one use-case entry in an existing feature file. `--file` is the
  destination feature YAML; supply the row payload either inline with
  `--use-case-json '{...}'` or from a JSON file with `--use-case-file <path>`.
  A row with `lifecycle: active` must include the conditionally-required fields
  (`actor`, `intent`, `preconditions`, `trigger`, `scenarios`,
  `observable_outcomes`, `host_applicability`, `verification_policy`,
  `approval_policy`).
- `matrix remove --repo <path> --use-case <id> --reason <text> --json`:
  mark a use case as `removed`. This is a lifecycle change, not physical
  deletion.

## Evidence

- `evidence record --repo <path> --use-case <id> --kind <kind> --result <result> --json`
  appends one evidence event.
- `evidence status --repo <path> --json` replays append-only JSONL history.
- `evidence void --repo <path> --evidence <id> --expected-head <event-id> --reason <text> --json`
  records a correction event without deleting history.

## Planning And Showcases

- `plan showcase --repo <path> --json` selects high-value live-demo items.
- `plan walkthrough --repo <path> --json` selects broader review coverage.
- `plan cards --repo <path> --plan-file <path> --json` renders presentation cards
  from a saved plan file.
- `capsule validate|list|plan --repo <path> --json` works with persisted demo
  capsules.
- `capsule run --repo <path> --capsule <id> --json` performs a persisted demo
  capsule as a live showcase run. Command steps stay pending unless
  `--execute-commands` is passed and the capsule permits command execution.
- `showcase start|record-observation|record-verdict|decide|pause|resume|finish|approve|reject|correct`
  records a mechanical showcase run ledger.

## Hosts And Doctors

- `host project --host <host> --repo <path> --dry-run|--write|--revert --json`
  projects or removes thin activation stubs.
- `host doctor --host <host> --repo <path> --json` checks profile and projection
  visibility.
- `host conformance --host <host> --repo <path> --json` checks one profile.
- `host conformance --all --repo <path> --json` checks Claude, Codex, Copilot,
  and OpenCode.
- `doctor roots|skills|package --repo <path> --json` checks workspace roots,
  canonical skills, and release packaging.

## Migration

- `migrate test-matrix --repo <path> --source TEST-MATRIX.md --dry-run --json`
  previews draft use cases.
- `migrate test-matrix --repo <path> --source TEST-MATRIX.md --out use-cases/_migrated --write --json`
  writes reviewed draft YAML. Old status and evidence stay review context only.
