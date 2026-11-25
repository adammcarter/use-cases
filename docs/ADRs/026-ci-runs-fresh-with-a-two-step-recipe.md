# ADR 026: CI runs fresh every time, with a two-step recipe and provider examples

## Status

Accepted - 2026-09-28

## Context

CI is where the tests run for everyone and the gate decides what merges. Two choices shape it.

**State.** The results store is not committed, so a CI job sees only the verdicts it makes itself. Carrying a store between CI runs, or committing hand-recorded verdicts, would let CI see more, at the cost of state to manage. The owner decided: "ultimately we're just running tests like a CI would but with our own markers around it to consider the use cases themselves as valid - this doesnt rely on any previous state or runs at all."

**Integration.** An official action for one CI provider would be convenient, but a product to maintain, and it would tie the design to one provider as the core is never tied to one test tool (ADR 010).

## Decision

- **The recipe:** `use-cases verify --run`, then `use-cases status --gate` (`--strict` on release branches), stopping at the first failure. Its exit codes are chapter 16's.
- **Fresh every run:** CI relies on no earlier state. Nothing is cached or restored. Nothing is stale in CI; anything unproven in the run is `unverified`, a warning under the default gate and a block under `--strict`. Keeping `.use-cases/runs/` as an artifact is for people only.
- **Your own test step** wraps it in `verify --start --json` (the `{report}` path) and `verify --finish`.
- **Sharded tests are one run:** start once, each shard writes a uniquely named file, and the finish job puts every file into the run's reports folder and runs `--finish --run-id`.
- **Provider recipes are examples** in `docs/ci/` (GitHub Actions, GitLab CI), each command in them checked against the command line. No official action for now; one can be added later without changing anything.

## Consequences

- Good: a CI result depends only on the commit it tested.
- Good: the same two commands work on any CI that can run commands.
- Cost: a route proved only by hand is `unverified` in CI, so it cannot pass a `--strict` gate there until hand-recorded verdicts can travel with the code (a later, additive design); until then such routes are marked non-gating.
- Cost: sharded CI moves the run folder and the shard files between jobs with the provider's own artifacts.

## Considered Options

- **Keep CI's store between runs:** saves little, adds state, and still never sees hand-recorded verdicts.
- **Commit hand-recorded verdicts now:** lets them gate CI, but needs its own design (what is committed, how it is reviewed, when it goes stale); left for later.
- **An official GitHub Action:** convenient, but a product to maintain and one provider favoured.

## Confirmation

- `test_ci.py`: the recipe from a clean checkout (nothing stale, the gate passes), a failing test failing the gate and not `verify`, tests split across four machines giving the verdicts of one run, overlapping shard files merging into one verdict each, and every recipe YAML block parsing.
- `CiRecipeCommandTests`: every `use-cases` command line in chapter 19 and the provider recipes is read by the real command line.

## Related Links

- `docs/design/19-ci.md`, `docs/ci/`
- ADR 010 (the core names no tool), ADR 022 (the command line), ADR 023 (the gate)
