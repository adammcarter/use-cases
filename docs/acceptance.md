# Acceptance Matrix

This repo dogfoods use-cases through `use-cases/`.

The rows cover matrix loading and mutation, evidence recording, live showcase
sign-off, command-backed demo capsules, generated-plan proof binding, host
projection conformance, MCP stdio parity and mutation, installable package
checks, and the sequential release gate. They are intended behavior rows, not
proof.

Proof remains in append-only ledgers or command output:

- `evidence/by-id/` contains the v1 dogfood evidence events.
- `showcase-runs/run.p14_v1_release_smoke_start/events.jsonl` contains the
  command-backed release smoke showcase.
- The final release gate is `use-cases scan … --policy-mode release` — every
  `required_for_release` row must be FRESH. It is the last step of the `prove`
  job in `.github/workflows/use-cases.yml`, and it runs *after* proofs are minted
  rather than before, or a newly required row would block the scan that has to
  precede the prove that would clear it. Every other run of `scan` — the same
  workflow's integrity job, and `.github/workflows/swift.yml` — passes
  `--policy-mode feature`, which blocks only INVALID.

  (It used to be `node scripts/release-gate.mjs`. That script went with the
  TypeScript at ADR 0007 row 10d, and `scripts/` no longer exists.)
