# CLI Reference

All commands use JSON envelopes with `schema_version`, `protocol_version`,
`command`, `ok`, `complete`, `data`, `diagnostics`, and `context`.

## Onboarding

- `ucm init [--repo <dir>] [--template generic|js-vitest|python-pytest|go-test] [--component <id>] [--force] [--json]`:
  scaffold a minimal working workspace — a `use-case-matrix.yml` (with a
  `verifiers.default` matching the template) and a `use-cases/example.yml` whose
  one row already validates. The scaffolded workspace passes `matrix validate`
  immediately. `init` never generates or writes a private key and never creates
  the GitHub workflow; it prints the next steps (key setup, CI workflow) instead.
  It refuses to overwrite an existing `use-case-matrix.yml` unless `--force`
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

## Markers & Trust

The trust flow ties a behaviour row to code and marks it `FRESH` only when trusted
CI has signed proof that the current code, binding, and verifier still match. The
signing key must be a PKCS8 ed25519 PEM — see
[key management](./security/key-management.md) for how to generate one.

- `ucm bind --row <id> --file <path> --mode explicit --start-line <n> --end-line <n> [--repo <path>] [--json]`:
  bind a row to a code span. `--mode explicit` inserts `//: @use-case: <id>` …
  `//: @use-case: end <id>` markers around the span (the comment prefix is inferred
  per file type). Use `--register-existing` to register a span whose markers are
  already present in the file instead of inserting new ones. Note: inserting the
  opening marker shifts the file's line numbers down by one, so a later `scan`
  reports the span one line below the `--start-line`/`--end-line` you passed —
  that is expected, not drift.
- `ucm scan [--repo <path>] [--public-key <pem>] [--keyring <path>] [--json]`:
  derive each row's freshness — `FRESH` / `SUSPECT` / `UNPROVEN` / `UNBOUND` /
  `INVALID` — from the current code, the binding registry, and the proof ledger.
  Without a trusted `--public-key` (or `--keyring`), signed proofs read `UNPROVEN`
  (the tool never trusts a signature it cannot verify).
- `ucm verify [--row <id> | --all] --out <path> [--repo <path>] [--json]`: run each
  bound row's verifier command and write an **unsigned** verification-results
  ledger (one JSONL record per row). This is the step that actually executes tests.
- `ucm prove (--row <id> | --all) --verification-results <path> --trusted-ci --signing-key-env <ENV> [--key-id <id>] [--append] [--repo <path>] [--json]`:
  mint **signed** ed25519 proof events from the `verify` results. Signing is
  CI-only: the private key is read from the named environment variable and never
  written to disk. A present-but-malformed key returns a `signing_key.invalid`
  diagnostic rather than crashing.
- `ucm validate-ledger [--repo <path>] [--json]`: check the append-only proof/
  evidence ledger for integrity (hash-chain, ordering, signature shape).

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
