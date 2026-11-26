# CI and hooks

Check use cases automatically: in CI, where the tests run for everyone and the gate decides what merges, and with git hooks on your own clone.

## The CI recipe

Two commands, in this order, stopping at the first failure:

```text
use-cases verify --run       run the tests in use-cases-bridge.yml and keep their verdicts
use-cases status --gate      does anything block?
```

| Command | Exit 0 | Exit 1 | Exit 2 |
|---|---|---|---|
| `use-cases verify --run` | the run finished with no run errors | run errors: a build failure, a missing report, a transformer error | refused: the workspace is INVALID |
| `use-cases status --gate` | nothing blocks | something blocks | refused |
| `use-cases verify --start` | the run is open, its run id and report paths printed | (never) | refused: the workspace is INVALID |
| `use-cases verify --finish` | the run was sealed with no run errors | run errors: a test step wrote no report, a build failure, a transformer error | refused: no started run, or the workspace is INVALID |

A failing test is not a `verify` failure: it is a verdict, and the gate decides whether it blocks. A run error is not a verdict: its routes get none, so they are `unverified` and the gate only warns. What fails CI for a run error is `verify --finish` (or `verify --run`) exiting 1.

## Install it in CI

Install one pinned version before the recipe, from the release tagged `v<version>` on the project's GitHub releases page:

```text
platform   macos-universal  ·  linux-x86_64  ·  linux-arm64
download   use-cases-<version>-<platform>.tar.gz  and  use-cases-<version>-<platform>.tar.gz.sha256
check      the tarball's sha256 must equal the one in the .sha256 file; fail the job if not
unpack     the whole tarball into one folder, and put its program on the PATH
```

- Write the version in the pipeline and change it on purpose; never "latest".
- Unpack the whole tarball: the program finds the files it ships with beside itself.

## Fresh every run

A CI job starts from a clean checkout with no `.use-cases/`, and the gate judges only what that job's run proved:

- a use case whose tests ran has this run's verdict;
- one whose tests did not run, or that is proven only by hand, is `unverified`: a warning, or a block with `--strict`;
- nothing is ever `stale` in CI, because nothing was proven there before.

Nothing needs caching between CI runs. Keeping `.use-cases/runs/` as a build artifact helps people read a failure (it holds the reports, the console output and the verdicts), but no later run reads it.

## Release branches

```text
use-cases status --gate --strict                   everything that gates must be proven
use-cases status --gate --strict --group release   only the release group, strictly
```

A route proven only by hand cannot pass a strict gate in CI. Mark it `gates_verification: false`, or gate it only where someone records it.

## Your own test step in CI

When the job runs the tests itself, wrap that step:

```text
use-cases verify --start --json      gives run_id, and reports.<validation id>: the path for each report
<your test step>                     writes its report to that path
use-cases verify --finish            reads it, judges, keeps the verdicts
use-cases status --gate
```

Read the path from the JSON with whatever the machine already has and pass it to your test step. The JSON is small and has one key to a line, so a line filter such as `sed` is enough; a minimal image may hold neither `jq` nor Python.

- The test step fails the job as usual: a failing test that no use case claims must still fail CI. Run `--finish` and the gate whether or not it failed (not when the job was cancelled, and only when `--start` succeeded), so the run is still sealed and judged.
- A test wrapper that already writes a report must write it to the path from `--start`, not to a second place, when the test tool takes its report option only once.
- Between `--start` and `--finish`, write no files that hold marker text into the checkout outside `discovery.exclude`: a second build folder that copies docs or sources would hold copies of the markers, and `--finish` refuses the workspace. Put build output outside the checkout, or exclude its folder.

## Tests split across machines

Shards of one test suite are one run:

```text
job 1    use-cases verify --start --json   then keep the run id, and save .use-cases/runs/<run id>/ as an artifact
shards   each tests the same commit and writes one uniquely named report file
job 2    restore .use-cases/runs/<run id>/, put every shard's file into reports/<validation id>/,
         then use-cases verify --finish --run-id <run id>, then use-cases status --gate
```

Give that validation no `report` name, so `{report}` is a folder that holds every shard's file. Each test must run in exactly one shard, and every shard must check out the same commit.

## Git hooks

Hooks run a check at a git moment, so nobody has to remember it. They are opt-in, and belong to one clone: nothing is committed, and nothing is added unless you ask.

| Hook | Git moment | Runs | Stops the commit or push when |
|---|---|---|---|
| `commit` | pre-commit | `use-cases validate` | the files are INVALID |
| `push` | pre-push | `use-cases status --gate` | something blocks |

Neither runs a test. The push hook reads the verdicts already kept, so a push whose use cases changed since they were proven is held until you run the tests again.

```text
$ use-cases hooks
commit   not installed  use-cases validate
push     not installed  use-cases status --gate
→ use-cases hooks add commit push

$ use-cases hooks add commit push
added the commit hook
added the push hook
commit   installed      use-cases validate
push     installed      use-cases status --gate

$ use-cases hooks remove push
removed the push hook
commit   installed      use-cases validate
push     not installed  use-cases status --gate
```

- `--dry-run` shows what would change.
- A hook file that is already there and not Use Cases' own is left alone: `hooks add` prints the line to add to it yourself, and exits 1.
- With a hook manager (git's `core.hooksPath` set), nothing is written: it prints the line for that manager's settings, and exits 1.
- A hook finds `use-cases` on the PATH, or else the copy that added it. With neither, it stops and says how to fix it; it never passes without checking.
- Git's own no-verify option skips a hook once, as for any git hook.
