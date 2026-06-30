# Data Model

Project data lives under the configured `data_root`; installed plugin code is
read-only.

## Directory layout at a glance

Two pairs of similarly-named paths are deliberately distinct — the dot-prefixed
ones are tool-managed machine state (like `.git`), the others are yours:

| Path | Owner | Holds |
|---|---|---|
| `use-cases/` | you (authored) | the sharded use-case matrix YAML |
| `.use-cases/` | the tool (machine state) | the code-marker **binding registry** + **signed proof** ledger + the trusted public key |
| `evidence/` | the tool (append-only) | **use-case evidence** events (observations, results) keyed by id |
| `showcase-runs/` | the tool (append-only) | performed **showcase run** event ledgers |

Don't confuse `evidence/` with the proof ledger: `evidence/` holds **use-case
evidence** (observations attached to use cases), while `.use-cases/proofs.jsonl`
is the marker-freshness **proof** ledger (CI-signed). The names now make the
distinction plain — proofs vs evidence. Both are append-only and content-addressed.

## Use Cases

Use cases are sharded YAML files under `use-cases/`. Each file describes one
feature and one or more behavior rows. Active rows include actor, intent,
scenarios, observable outcomes, host applicability, verification policy, and
approval policy.

Damaged YAML does not bring the matrix down. Valid siblings stay addressable and
diagnostics explain damaged files, duplicate IDs, broken references, and unsafe
paths.

## Evidence

Evidence is append-only JSONL under `evidence/`. Corrections, voids,
invalidations, and supersessions are new events. Normal workflows do not rewrite
or delete old lines.

## Showcases

Showcase runs are append-only JSONL under `showcase-runs/<run-id>/events.jsonl`.
Prepared plans are not proof. A run becomes proof only after observations,
verdicts, finish events, and any required approval are recorded.

## Demo Capsules

Demo capsules are optional persisted scripts under `demo-capsules/`. Most runs
can stay ad hoc; persisted capsules are best for smoke demos and common golden
paths.

## Host Profiles

Host profiles under `hosts/` define expectations for Claude, Codex, Copilot,
and OpenCode. A profile is not support proof. Conformance and evidence state are
separate.
