# ADR 006: `validate --begin` + `validate` for your own runs, `validate --run` for the core's

## Status

Superseded by [ADR 013](013-validate-start-and-finish-are-named.md) - 2026-09-25

## Context

`use-cases validate` is the entry point for validating use cases. Sometimes the tool should start the tests. Sometimes they run elsewhere: in an IDE, in a CI step, by hand. One command that sometimes runs tests and sometimes doesn't is confusing, and a command that reads whatever report happens to exist can't prove the report is new (ADR 005).

## Decision

Three explicit requests, one pipeline:

```text
use-cases validate --begin   begin point: note the code, delete old reports
   (you run your tests, asking the tool for a report)
use-cases validate           finish point: read the reports, judge, guard, seal

use-cases validate --run     begin point → run the commands in the project → finish point
```

- `validate` never starts anything. It finishes the latest begun run, and is refused when there is none.
- `validate --run` runs each selected command after deleting its old report. A validation with no run command is a run error under `--run`, never an old report read silently.
- `--only <ids>` narrows `--run` or `--begin`. The finish step reads what its begun run selected and refuses `--only`.
- `use-cases record` stores a verdict for one route directly, for manual checks.

## Consequences

- Good: it's always clear whether anything will run.
- Good: results from tests run anywhere can be recorded, with the same guarantee as `--run`.
- Good: CI fits naturally: `validate --begin` as one step, the usual test step, `validate` as the next.
- Cost: running your own tests is three steps, not one.
- Cost: tests you run yourself must ask the tool for a report, because many tools write none by default.

## Considered Options

- **`validate` reads whatever report exists, checked against its start time:** one step fewer, but see ADR 005: not every tool records a time, and a late one misses edits.
- **One command that runs tests only when no report exists:** hidden behaviour, and it could read a stale report.
- **The core always runs the tests:** no way to use results from CI or an IDE.

## Confirmation

These checks failed when their rule was removed:
- `test_validate_never_runs_tests`
- `test_validate_without_a_begin_is_refused` and `test_a_finished_run_cannot_be_finished_again`
- `test_run_never_reads_a_report_left_by_an_earlier_run` and `test_run_never_reads_a_report_it_did_not_produce`
- `test_begin_only_reads_only_what_it_began` (`--only` with `--begin`)

`test_validate_uses_the_report_from_tests_you_ran_yourself` shows both forms give the same verdicts.

## Related Links

- `docs/design/13-verify-flow.md`
- `docs/design/14-run-commands.md`
