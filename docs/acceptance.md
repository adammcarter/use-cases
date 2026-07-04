# Acceptance Matrix

This repo dogfoods use-cases through `use-cases/`.

The rows cover matrix loading and mutation, evidence recording, live showcase
sign-off, command-backed demo capsules, generated-plan proof binding, host
projection conformance, MCP stdio parity and mutation, TEST-MATRIX migration,
installable package checks, and the sequential release gate. They are intended
behavior rows, not proof.

Proof remains in append-only ledgers or command output:

- `evidence/by-id/` contains the v1 dogfood evidence events.
- `showcase-runs/run.p14_v1_release_smoke_start/events.jsonl` contains the
  command-backed release smoke showcase.
- The final release gate remains `node scripts/release-gate.mjs`.
