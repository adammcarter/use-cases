# 13 — Verify Flow

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

The verify flow turns test runs and recorded verdicts into stored evidence.

It defines these requests:

```text
use-cases verify --start    note the code, print the run id and its report paths; then you run your tests
use-cases verify --finish   finish a started run: read the reports your tests wrote   [--run-id ID]
use-cases verify --abort    close a started run nobody will finish                    [--run-id ID]
use-cases verify --run      --start, run the commands in the bridge settings, --finish
use-cases record            record a verdict for one route directly
use-cases verify            runs nothing; names the steps above
```

`verify` is named for what it produces: verified use cases. Checking that the authored files are right, without running any test, is `use-cases validate` (chapter 09).

and the one guard that decides whether a result still describes the code it will be stored against.

Chapter 10 defines the bridge settings and transformers. Chapter 14 defines how run commands execute. Chapter 07 defines how the core judges results. Chapter 12 defines how a run is stored.

## 2. One pipeline, a start point and a finish point

Every verify run has a **start point** and a **finish point**. Between them the tests run, writing their reports into the run's own folder. `--run` is exactly `--start`, then the bridge's run commands, then `--finish`, through the same code; the only thing it adds is the step in the middle.

```text
              start point                                      finish point
                   │                                                │
 verify --start  ├─ note fingerprints + file digests              │
                   ├─ create runs/<id>/reports/<validation>/        │
                   ├─ print the run id and each {report} path       │
                   │                                                │
                   │    the tests run: terminal, IDE, CI step,      │
                   │    or --run's commands; each writes {report}   │
                   │                                                │
 verify --finish │                                                ├─ read each report in place → transformers
                   │                                                ├─ merge, judge (chapter 07)
                   │                                                ├─ guard: code changed in between?
                   │                                                └─ seal the run (chapter 12)

 verify --run    = --start → run each command with its {report} → --finish, in one request
```

```text
                       --run                             --start, then --finish
                       ─────                             ──────────────────────
who starts tests       the core                          you, your IDE, CI, anything
where they run         the real project                  wherever you ran them
report                 written to {report} by the        written to {report} by your run
                       run command
the guard              code changed during the run       the same guard
build failure          detected from the exit code       no report, or an incomplete one
```

No timestamp decides anything, and nothing is deleted. A report is trusted because it is in the run's own folder, which did not exist before the start point; a verdict is kept because the code its route depends on is the same at the finish point as at the start point.

## 3. Tests run in the real project

`--run` launches each run command in the workspace itself, exactly as typing the command in a terminal would (chapter 14).

Nothing is frozen or copied. Build caches, incremental compilation, and tool state behave normally. Correctness comes from the start point and the guard, not from isolation.

## 4. Preconditions

A request begins by synchronizing the Workspace Model (chapter 09) and reading one consistent revision.

```text
workspace INVALID        -> request refused, no run allocated
synchronization conflict -> request refused, no run allocated
--only names an unknown validation
                         -> request refused, no run allocated
workspace valid          -> continue
```

Only READY use cases receive verdicts. DRAFT and INVALID use cases are skipped silently by the judge; they never receive a result.

## 5. Reference sequence: `use-cases verify --start`

```text
1.  synchronize model; read revision R_start
2.  select validations (all, or --only)
3.  compute every route fingerprint and a digest of every linked and resource file from R_start
4.  allocate run (kind: verify)
5.  create reports/<validation-id>/ in the run folder for every selected validation
6.  write start.json, recording the selected validations exactly (chapter 12)
7.  return the run id and each selected validation's {report} path; the run stays open
```

Step 5 is what makes a later report trustworthy: the folder is new, and it belongs to this run, so whatever the finish point reads was written after the start point. Nothing outside the run is touched, and no report is ever deleted.

With `--json` (chapter 16):

```json
{
  "output_version": 1,
  "command": "verify",
  "step": "start",
  "run_id": "0192f0c4e5a17c3e9b04d2f61a8c3b57",
  "started": true,
  "selected": ["unit-tests"],
  "reports": {"unit-tests": "/work/shop/.use-cases/runs/0192f0c4e5a17c3e9b04d2f61a8c3b57/reports/unit-tests/results.xml"},
  "notes": ["now run your tests, each writing its report to the path in `reports`; then `use-cases verify --finish --run-id 0192f0c4e5a17c3e9b04d2f61a8c3b57` records their results"]
}
```

`--start` never touches another run. Several started runs may be open at once, for example two CI jobs in one checkout; each has its own reports folder and is finished by its id. Nothing is judged at start.

## 6. Reference sequence: `use-cases verify --finish`

```text
1.  choose the run: the one named by --run-id, or the only open started run
      none open        -> request refused: "no started run ..."
      several open     -> request refused, listing them: name one with --run-id
      --only given     -> request refused: the selection was made at the start point
      only runs --start opened are chosen; a run --run opened is finished by that request alone
      (named with --run-id, it is refused: still running, or stopped and to be aborted)
2.  take the run's lock; a second --finish of the same run is refused, never interleaved
3.  the finish point (section 7)
```

`--finish` never starts anything. A finished run cannot be finished again.

`--abort` seals a started run as interrupted, with no results, and the note "aborted": any result lines staged by an unfinished `--finish`, whole or torn, are dropped, since staged lines are never evidence. It is how a started run nobody will finish is closed; an open run is never evidence either way. Its reports stay in its folder. `--abort` needs only the results store, not the model: a workspace that does not load (an INVALID use case file, a links transformer that fails) never keeps a run open. A run whose own files are damaged is refused by name, never skipped.

Plain `use-cases verify`, with none of `--start`, `--finish` or `--run`, runs nothing: it names the three steps and exits.

## 7. The finish point, and `use-cases verify --run`

`--run` is `--start`, the run commands, and `--finish`, sharing their code:

```text
--run:
1.  the start point (section 5), taking the run's lock before start.json is written,
    so no --finish can pick the run up; the lock is held until the seal
2.  for each selected validation, in file order (chapter 14):
      a. no run command       -> run error "no run command: run its tests yourself between
                                 `use-cases verify --start` and `use-cases verify --finish`"
      b. run the command in its working folder, with {report} replaced; capture console output
3.  the finish point, below, knowing each command's exit code

the finish point (--finish and --run):
1.  the selected validations in use-cases-bridge.yml must be exactly those start.json recorded
      changed          -> request refused: start again, so the settings and the reports match
2.  synchronize model; read revision R_finish; compute the link set
3.  for each selected validation, in file order:
      a. its command could not run  -> that run error (chapter 14)
      b. nothing at {report}, or an empty reports folder
                                    -> run error "no report: nothing was written to reports/<id>..."
      c. digest reports/<validation-id>/; call the transformer's results job on the report in place
         (exit_code: the command's, or null when you ran the tests); digest again
      d. transformer error          -> run error; no results from this source
      e. digests differ             -> run error "report changed while it was read"; no results from this source
      f. non-zero exit and no fail/error result
                                    -> run error "command exited N without any failing test (build failure?)";
                                       no results from this source
4.  merge results from every source
5.  judge every READY route (chapter 07), with the fingerprints from start.json;
      a route not in start.json (added since the start point)
                                    -> no verdict: "code changed during the run"
6.  synchronize model; apply the guard (section 8)
7.  append results, finalize manifest, seal with the report digests as read (chapter 12)
```

So running the same tests with `--run`, or with `--start`, your own command writing to `{report}`, and `--finish`, stores the same verdicts and diagnostics. Only the sources differ: under `--run` they also say which command ran, its exit code and how long it took.

`--run` reads only reports its own commands wrote into its own run. A validation without a run command has no command to run, so it is a run error under `--run`.

`--only <validation-id>` restricts the selection (chapter 14). Routes whose links receive no result from the selected sources get no verdict, as always.

## 8. The guard: code changed during the run

The start point notes every route's fingerprint. The finish point computes them again.

```text
fingerprint at start  ==  fingerprint at finish   -> keep the verdict
otherwise                                          -> no verdict: "code changed during the run"
```

A route's fingerprint covers exactly what its verdict depends on (chapter 11): the use case's wording, its implementation links, the route's validation links, and its resources. So the guard catches edits to linked code, linked tests, resources and the use case itself, and nothing else. An edit to another region of the same file, or to an unrelated file, affects no verdict — and would not make the route stale afterwards either.

The diagnostic names the files whose digests changed between start and finish, so a person can see what moved.

Because the start point is taken before any test starts, an edit made while a tool builds is caught. The guard is the same for `--run` and for tests you run yourself.

The guard compares two moments, not everything in between. An edit made after the start point and undone before the finish point is not seen: the verdict is stored against the start-point code, which the tests may not have run on. That is the cost of running tests in the real project with no frozen copy (ADR 005). Only an edit that is reverted mid-run creates this window.

## 9. Merge, then judge

Results from every source merge before any route is judged.

```text
source auth-tests      → results for links A, B, C
source session-tests   → results for link D
                                 │
                            one merged set
                                 │
                    judge each route once (chapter 07)
```

A route whose validation links are spread across several test runs is judged once, from all of them. Each route receives at most one result per run (chapter 12).

The judging rules are chapter 07's:

- every validation link needs at least one result, otherwise no verdict ("its test didn't run");
- a fail beats "didn't run";
- worst result wins;
- tests inside no link are reported as unlinked tests.

## 10. Run errors

Run errors are problems with a source, not with behaviour.

```text
no report: nothing was written to reports/<id>...
report changed while it was read
no run command: run its tests yourself between `use-cases verify --start` and `use-cases verify --finish`
transformer error, no results used: <reason>
command exited N without any failing test (build failure?)
command timed out after N seconds
command could not be launched: <reason>
command terminated abnormally (signal N)
```

A run error:

- is recorded in the run manifest (chapter 12);
- gives no verdict to any route from that source;
- never makes a route `failed`;
- does not affect other sources in the same run.

Some tools exit non-zero for results that are not failures, for example a strict mode that fails the run on pending tests. The exit-code rule still applies: the run command turns such a mode off, or the source is a build failure. The rule stays because it is what refuses a half-written report.

## 11. Route verdicts are fingerprinted at the start point

Each stored result carries the route fingerprint from the start point (chapter 11). The guard ensures the finish point agrees; when it does not, the route gets no verdict.

A result may be stored and immediately derive as `stale` when the model advances after the request completes. That is correct: the result remains valid evidence for its fingerprint, and becomes applicable again if the workspace returns to that state (chapter 12).

## 12. `use-cases record`

```text
use-cases record <use-case-id> <route-id> <status> [message] [--attach <file>...]
```

`record` stores one verdict for one route, supplied by a person, agent, or automation. It covers:

- routes with a `procedure` (manual acceptance, walkthroughs, showcases);
- routes verified by hand or by an agent outside any test tool;
- any route, when someone deliberately records evidence for it.

```text
1.  synchronize model; read revision R
2.  the route must exist on a READY use case; status must be pass, fail, incomplete or error
3.  compute the route fingerprint from R
4.  allocate run (kind: record)
5.  ingest attachments
6.  append { status, message, via: ["record"] }
7.  seal
```

Displaying or attempting a procedure never implies a verdict. Only an explicit `record` does.

The latest matching result wins, whichever request produced it (chapter 12).

## 13. No bridge settings

With no `use-cases-bridge.yml`, or with no validations in it:

```text
use-cases verify --start   -> nothing to start; no run written
use-cases verify --finish
use-cases verify --run     -> nothing to read; no run written; the note
                                "no validations set up in use-cases-bridge.yml, so nothing to read;
                                 record verdicts with `use-cases record`"
```

Use cases, links, `record`, and status all work without helpers.

## 14. Explicit requests always run

`verify --run` runs every selected validation, even when every route it could affect is already verified. Skipping work is not part of the verify flow in v1 (chapter 15).

## 15. Cancellation and aborted runs

Cancelling a request stops starting new commands and terminates an active one (chapter 14). Ctrl-C, SIGTERM and a closed terminal (SIGHUP) all cancel, except a closed terminal the core was told to ignore, as `nohup` does; a second one stops the core at once. A request cancelled before it writes anything writes nothing. One that is already writing its run, a short `--start` or `record`, finishes that write and then reports it as done, with a note that the cancellation came too late to stop it. Every command answers a cancellation promptly, the read-only ones included, with one limit. On a machine where the cooperative thread pool has a single thread (a one-core machine or container), a first Ctrl-C, SIGTERM or closed terminal that arrives while a command is doing synchronous work, such as loading the workspace or hashing, is not seen until that work ends; the command then gives its own answer as if no signal had come. A second signal still stops the core at once, because the handlers reset themselves after the first. With two or more threads the first signal is answered promptly, and a write that has begun is never abandoned in either case.

```text
cancelled before judging    -> no results; run sealed as interrupted
cancelled after judging     -> results already appended are kept; run sealed as interrupted
started, never finished     -> open until `--abort` closes it; an open run is never evidence (chapter 12).
                               This holds for a `record` run cut off mid-write too
the core itself killed      -> the run stays unsealed and is never evidence. A run `--run` opened is never
                               finished by `--finish`: its reports may be half written and its exit codes
                               are lost. `--abort` closes it; it blocks nothing else
```

The manifest lists which sources were not processed. No verdict is invented for them.

## 16. Concurrency and sharded CI

Separate requests may run at the same time. Each has its own run folder and run id (chapter 12); run ids follow time, so a slower older request never replaces a newer request's matching result. A run being finished is locked: nobody else can finish or abort it meanwhile.

Tests sharded across several machines are one run:

```text
job 1        use-cases verify --start            (prints the run id and the reports folder)
shards       each machine tests the same commit and writes its own file into the validation's reports folder
             (copied back to the job that started)
job 2        use-cases verify --finish --run-id <id>
```

A validation with no report name hands its tests the whole folder (chapter 10), so the shards' files together are one report and every link gets its result, whichever shard ran it. The start point's guarantee holds: the folder was created at the start point, and the shards test the commit that was started.

Two `--run` requests running the same test tool in the same project may interfere with each other's build state. The core does not prevent this; the guard still withholds verdicts whose code changed.

## 17. Security

Run commands and transformers run with the permissions of the Use Cases process. The core provides no sandbox (chapter 14).

## 18. Final model

```text
                    use-cases-bridge.yml
                            |
                     verify --start ─────────────── the start point
                     note the code; runs/<id>/reports/
                            |
          +-----------------+------------------+
          |                                    |
   --run: the core runs                  you run the tests
   each command with {report}            with {report}
          |                                    |
          +-------> runs/<id>/reports/ <-------+
                            |
                     verify --finish ────────────── the finish point
                            |
                       transformers
                      result per link
                            |
                     merge all sources
                            |
                     core judges (07)
                            |
            guard: code changed since the start point?
                            |
                   run sealed, reports and all (12)

   use-cases record ──────────────────────────► results saved (12)
```

The key invariant:

> A stored verdict describes the code its fingerprint names. The run's own reports folder proves the report is new; the guard proves the code at the finish point is the code at the start point. When either cannot be established, the route gets no verdict. Nothing is ever deleted to make this true.
