# ADR 016: Started runs are named and locked, and run ids follow time

## Status

Accepted - 2026-09-25

Its command names are superseded by [ADR 021](021-verify-runs-tests-validate-checks-files.md): `validate --start/--finish/--run` is now `verify`, and `--abandon` is `--abort`.

Supersedes [ADR 013](013-validate-start-and-finish-are-named.md).

## Context

An adversarial audit of the store reproduced five failures, each of which would have forced a breaking change once teams depended on the store:

- **Two `--start`s in one checkout corrupted a sealed run.** `--start` sealed any other open run, `--finish` took "the latest", and sealing wrote files before checking for an existing seal. Two CI jobs racing left a sealed run whose digests no longer matched, and `status` then failed for every route.
- **Merged stores ordered by chance.** The first run id was random and later ones counted up, so a CI pass from yesterday could outrank a developer's fail from today. Two shards forked from one cache allocated the same id.
- **A newer core's run made the whole store unreadable** to an older core, and nothing said which fields a reader could rely on.
- **`--finish` read whatever the settings said at finish time.** A branch switch could point it at an old report after `--start`.
- **Sharded CI had no sanctioned flow.**

## Decision

- `--start` prints its run id and never touches another run. `--finish` and the new `--abandon` take `--run-id`. The id may be left out only when exactly one started run is open.
- The process finishing, abandoning or sealing a run holds that run's lock. A second one is refused, never interleaved. Sealing checks for `completion.json` before writing anything.
- A run id is `max(last + 1, milliseconds since 1970 << 80 | 80 random bits)`. Ids only go up locally, sort by time across machines, and forks don't collide. A store copied without `run-order.json` keeps working.
- Every run version keeps one envelope forever: run ids, `result_count`, the manifest and log digests, and each result's `use_case`, `route`, `fingerprint` and `status`. A reader ignores unknown fields, and reads a newer version through the envelope alone.
- `start.json` records the selected validations exactly. `--finish` refuses if they changed.
- Sharded CI is one run: one `--start`, every shard's report written into the validation's report folder, then one `--finish --run-id`.

The command names from ADR 013 stay: `--start`, `--finish`, `--run`, and plain `validate` running nothing.

## Consequences

- Good: concurrent jobs, merged stores and mixed core versions all give the same answer on every machine, with no migration.
- Good: a forgotten started run is closed explicitly and can never be mistaken for another.
- Cost: when several runs are open, `--finish` needs the id, so CI scripts pass it along.
- Cost: across machines, order is only as good as their clocks. Within one store it is exact.

## Considered Options

- **Keep "finish the latest":** simplest, but it's the flow that corrupted stores under concurrency.
- **A global counter service:** exact ordering, but a dependency every repo would need.
- **Reject newer run versions:** safe for an old reader, but every mixed-version team would break on every upgrade.

## Confirmation

- `test_two_open_runs_must_be_named_and_never_touch_each_other`, `test_a_run_being_finished_cannot_be_finished_twice_at_once` and `test_finish_refuses_when_the_bridge_settings_changed_since_start` (`test_helpers.py`).
- `test_run_ids_only_go_up_and_follow_time_across_machines`, `test_stores_from_two_machines_merge_and_the_newer_verdict_wins`, `test_a_copied_store_without_its_allocation_file_keeps_working` and `test_a_run_from_a_newer_core_is_read_through_its_envelope` (`test_store.py`).

## Related Links

- `docs/design/12-results-storage.md` §8, §9, §18, §25, §32
- `docs/design/13-verify-flow.md` §5, §6, §16
