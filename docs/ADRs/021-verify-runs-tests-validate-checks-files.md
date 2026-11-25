# ADR 021: `verify` gets verdicts from tests, `validate` checks the files

## Status

Accepted - 2026-09-26

Supersedes the command names in [ADR 016](016-runs-are-named-locked-and-time-ordered.md) and [ADR 020](020-each-run-owns-its-reports.md). Their behaviour stands.

## Context

The request that gets verdicts from tests was called `validate` (`--start`, `--finish`, `--run`, `--abandon`). Shaping the command line raised two problems:

- A newcomer expects `validate` to mean "are my files right?", as it does in other tools. There was no command for that, and adding it as a flag (`validate --yml`) would mix a file check into a command whose flags are all steps of a test run.
- `--abandon` was an unfamiliar word for "stop the thing in progress". git uses `--abort` for that (`git rebase --abort`, `git merge --abort`).

Nothing had shipped, so no store, script or user depends on the old names.

## Decision

```text
use-cases validate                  are the authored files right? loads everything, runs no test, writes nothing
use-cases verify --start            the start point (unchanged behaviour)
use-cases verify --finish           the finish point
use-cases verify --run              --start, the run commands, --finish
use-cases verify --abort            close a started run nobody will finish (was --abandon)
use-cases verify                    runs nothing; names the steps
```

- `verify` is named for what it produces: verified use cases.
- `validate` is the loader on its own (chapter 09). An INVALID workspace fails it, as it fails every other request.
- A verify run's `kind` in `run.json` is `verify`.
- Chapter 13 is now "Verify flow" (`13-verify-flow.md`).
- The YAML words stay as they are: a use case's `validation:` routes and the bridge's `validations:` describe how behaviour is proved, which is still what they are.

## Consequences

- Good: each command does one kind of job, and its name says which.
- Good: `use-cases validate` is fast and safe to run on every save, commit or pull request.
- Cost: `validate` (a command) and `validation:` (a YAML key) now name different things. The key is about how a use case is proved; the command checks files. The chapters use each word only in its own sense.
- Cost: every chapter, schema description, test, canvas board and explainer that named the old commands changed in one sweep.

## Considered Options

- **`validate --yml`:** keeps one verb, but mixes a file check into the test-run steps, and allows meaningless combinations such as `--yml --run`.
- **No file-check command:** every command already refuses an invalid workspace, so `status` would double as the check. Cheaper, but less obvious to a newcomer.
- **`check` for the files:** clear, but a third verb beside `validate` and `verify` would make three words for "is it right?".

## Confirmation

These acceptance tests pin the rule:
- `test_validate_checks_the_files_and_nothing_else` (it writes no store, and refuses an invalid file)
- `test_plain_verify_asks_which_step`
- `test_two_open_runs_must_be_named_and_never_touch_each_other` (`--abort` closes the run left open)
- the acceptance suite drives `verify`, and the schema hook checks each run's `kind`

## Related Links

- `docs/design/09-workspace-loading.md` §1
- `docs/design/13-verify-flow.md` §1
