# ADR 013: `validate --start` and `validate --finish` for your own runs, `validate --run` for the core's

## Status

Superseded by [ADR 016](016-runs-are-named-locked-and-time-ordered.md) - 2026-09-25

Supersedes [ADR 006](006-begin-then-validate-or-validate-run.md).

## Context

ADR 006 named the two ends of a run you start yourself `validate --begin` and plain `validate`. Only one end had a name: plain `validate` quietly meant "finish the begun run", which the user found hard to follow. ("i dont get the 'validate' changes".) A name like `--begin-watch` was considered and rejected because nothing keeps running in the background: the first step takes a snapshot and exits.

The behaviour of ADR 006 is unchanged. This decision is about the names.

## Decision

Both ends are named, and plain `validate` runs nothing:

```text
use-cases validate --start    start point: note the code, delete old reports
   (you run your tests, asking the tool for a report)
use-cases validate --finish   finish point: read the reports, judge, guard, seal

use-cases validate --run      start → run the commands in the project → finish

use-cases validate            runs nothing: names the three steps and exits
```

- `--finish` never starts anything. It finishes the latest started run, and is refused when there is none.
- `--run` runs each selected command after deleting its old report. A validation with no run command is a run error under `--run`.
- `--only <ids>` narrows `--run` or `--start`. `--finish` reads what its started run selected and refuses `--only`.
- The same words are used everywhere: the start point, the finish point, `start.json`, `started_at`, `start_sha256`.
- `use-cases record` stores a verdict for one route directly, for manual checks.

## Consequences

- Good: CI scripts read as a matched pair: `validate --start`, the usual test step, `validate --finish`.
- Good: typing plain `validate` can never do something surprising; it explains the choice.
- Cost: every command is one word longer than before.
- Cost: the stored file and field names changed with the words (`begin.json` became `start.json`). Nothing had shipped, so no stores needed migrating.

## Considered Options

- **Keep `--begin` + plain `validate`:** shortest, but the second half is invisible.
- **`--begin-watch`:** suggests a background watcher that doesn't exist.
- **Subcommands, `validate start` / `validate finish`:** also clear, but `--run` would then be the odd one out.
- **Plain `validate` means `--run`:** convenient, but a bare command that starts your test suite is the hidden behaviour ADR 006 set out to avoid.

## Confirmation

These checks failed when their rule was removed:
- `test_plain_validate_asks_which_step`
- `test_finish_without_a_start_is_refused` and `test_a_finished_run_cannot_be_finished_again`
- `test_only_is_chosen_at_start_not_at_finish`
- `test_tests_you_ran_yourself_between_start_and_finish`, in all nine fixture repos

## Related Links

- `docs/design/13-verify-flow.md`
- ADR 005 (why there is a start point at all)
