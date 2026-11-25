# `exit-code` transformer

**Job:** results · **State:** built, proven in `UseCases/Acceptance/test_helpers.py`

Gives every validation link in one file the same result, based on the run command's exit code. It fits a script that is itself the check: a linter, a smoke script, a migration dry run.

## Setup

```yaml
validations:
  - id: style
    report: style.txt
    run: [sh, -c, 'sh scripts/check.sh > "$1"', sh, "{report}"]
    transformer: exit-code
    settings:
      file: scripts/check.sh
```

## Behaviour

| Exit code | Result for every validation link in `settings.file` |
|---|---|
| 0 | `pass` |
| anything else | `fail` |

## Limits

- It needs an exit code, so it works only with `use-cases verify --run`. Read after `verify --start`, it returns no result and a diagnostic, so the core reports "its test didn't run".
- Like every source, the command must leave a report at `{report}`, because a missing report is a run error. Its contents are not read.
- It can't tell tests in the same file apart: one failing test fails every link in the file. A per-test transformer for the tool removes this limit.
