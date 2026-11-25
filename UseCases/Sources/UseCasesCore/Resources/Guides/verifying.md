# Verifying

Run your tests through Use Cases to get a verdict for each use case, record a verdict by hand, and close runs nobody will finish.

## How a verdict is made

```text
use-cases-bridge.yml  ──  which command runs the tests, and which transformer reads its report
verify                ──  runs the command, has the report read, keeps one verdict per route
status                ──  shows the verdicts, and whether anything blocks (--gate)
```

Verdicts are kept in `.use-cases/` in this checkout only, like test results: they are never committed, and a fresh checkout has none until you run.

## The bridge settings

`use-cases-bridge.yml` lists your test commands as `validations`. Example, for a project whose tests are a shell script that writes a JUnit XML report:

```yaml
schema_version: 1

validations:
  - id: unit-tests
    report: results.xml
    run: [sh, tests/total-test.sh, "{report}"]
    transformer: junit
    settings: { find: file-name }
```

| Field | Means |
|---|---|
| `id` | the name of this command's verdicts and of its reports folder; it need not match a route id |
| `run` | the command, one argument per item; no shell unless you start one |
| `report` | the report's file name; without it, `{report}` is a folder (for tools that write one file per test class) |
| `{report}` | replaced by the absolute path where this run's report must be written |
| `transformer` | what reads the report: a bundled name, or a path to your own program |
| `settings` | passed to the transformer unchanged |
| `working_dir` | the folder the command runs in, for a sub-project |
| `timeout_seconds` | stop the command after this long |

The bundled transformers, by the report they read. Each is named for the report format or the test tool it reads; the tools named are examples, not the only ones that work:

| Transformer | Reads |
|---|---|
| `junit` | JUnit XML, which many test tools write when asked |
| `go-test-json`, `cargo-test`, `swift-test`, `swift-testing` | the report of one particular test tool each |
| `cucumber-messages` | the Cucumber message stream |
| `exit-code` | nothing: the command's exit code is the result for every link in one file |

Your tests must write a report at `{report}`: most test tools write one only when asked, so the command asks for it.

## Run the tests and keep the verdicts

```text
$ use-cases verify --run
run 01a20580 · 1 verdict (1 pass) · 0 run errors
→ use-cases status --gate
```

- `--only unit-tests` runs only the validations named (comma-separated).
- A failing test is a verdict. `verify` exits 0 and `status` shows the use case failed.
- A **run error** (the command failed without any failing test, no report was written, a transformer failed) exits 1. Verdicts judged before it are kept:

```text
$ use-cases verify --run
run 01a20582 · 0 verdicts · 1 run error
  ! unit-tests: command exited 1 without any failing test (build failure?)
→ use-cases status --gate
```

Plain `use-cases verify`, with no step, runs nothing and names the steps.

## Your own test step

When something else runs the tests (your own script, an IDE, a CI step), wrap it in `--start` and `--finish`:

```text
$ use-cases verify --start
started run 01a20956b18b51ac3788559c0740405d
  unit-tests   write the report to …/.use-cases/runs/01a20956b18b51ac3788559c0740405d/reports/unit-tests/results.xml
→ run your tests, then: use-cases verify --finish --run-id 01a20956b18b51ac3788559c0740405d

$ sh tests/total-test.sh .use-cases/runs/01a20956b18b51ac3788559c0740405d/reports/unit-tests/results.xml

$ use-cases verify --finish --run-id 01a20956b18b51ac3788559c0740405d
run 01a20956 · 1 verdict (1 pass) · 0 run errors
→ use-cases status --gate
```

- `use-cases verify --start --json` gives `run_id` and `reports`, the path for each validation, for a script to read.
- `--finish` compares the code with how it was at `--start`. Code that changed in between gets "code changed during the run" instead of a verdict.
- The `exit-code` transformer needs the exit code, so it only works with `--run`.

## Runs nobody will finish

A started run stays open until `--finish` or `--abort`. With several open, name one:

```text
$ use-cases verify --abort
error: several runs are open (01a2057f65c6913daea8eb49582e810e, 01a2057f672dd3e5ea53c2b1617ec191): name one with --run-id
$ use-cases verify --abort --run-id 01a2057f65c6913daea8eb49582e810e
aborted run 01a2057f65c6913daea8eb49582e810e
```

Run ids are ordered by time, so runs started close together share their first digits. Always pass the full id.

## Record a verdict by hand

A "try it" route (one with a `procedure`) is proven by someone performing its steps. Record what they saw:

```text
$ use-cases record basket.discounts try-it pass "tried by Sam, live, on the test build" --attach receipt.txt
recorded: basket.discounts / try-it → pass
→ use-cases status basket.discounts
```

- The values are the use case, the route, and `pass`, `fail`, `incomplete` or `error`, then an optional message. An id may be shortened to any prefix that names only one.
- `--attach` keeps files as evidence with the verdict: a screenshot, a recording, an output file.
- `use-cases record --interactive` asks for each value, in a terminal only.
- Only a READY use case can be recorded. A verdict recorded by hand goes out of date like any other.

## Is it proven now?

```text
$ use-cases status --gate
gate: clear
```

`use-cases status --gate` exits 1 when something blocks; `--strict` blocks on anything unproven too. What each status means, and which ones block, is in `use-cases docs reading-status`.

## Keeping the store small

Every run adds a folder to `.use-cases/`, and none is deleted on its own. `use-cases status` shows the store's size, and how many runs a later run has superseded and status no longer uses. Remove those with:

```text
$ use-cases prune --dry-run
would remove  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB

would remove 1 run · would free 7.8 KB

$ use-cases prune
removed  run 01a20e8224b8b82ea0fdc1e39430a016  7.8 KB

removed 1 run · freed 7.8 KB
```

Prune judges the workspace as `status` does and keeps every run `status` reads now, so it changes no status or gate answer, even when the code is back at an older state; an INVALID workspace is refused and nothing is removed. It never touches a run that is started and not finished, and it is not an agent tool: deleting evidence is a person's call.

## For agents

The `use_cases_verify_tests` tool takes `step` (`start`, `finish`, `run` or `abort`), `only` (a list) and `run_id`. The `use_cases_record_verdict` tool takes `use_case`, `route`, `status`, `message` and `attach` (a list). Each returns the same document as `--json`.
