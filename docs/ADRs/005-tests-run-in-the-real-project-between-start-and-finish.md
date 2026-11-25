# ADR 005: Tests run in the real project, between a start point and a finish point

## Status

Accepted - 2026-09-25

Its report handling is superseded by [ADR 020](020-each-run-owns-its-reports.md): each run owns its reports, and nothing is deleted.

## Context

A stored verdict must describe the code it was produced from. Two things can break that:

- the report is old: it was written before the code it would now verify;
- the code moved: someone edited linked code while the tests were running.

Copying the project to a frozen snapshot before testing prevents both, but changes how tests behave. Validating should be the same as running the tests yourself. Report timestamps can't be trusted either: some tools record none (Maven Surefire, `cargo test`), and others record them only after building (about 3.5 s late for Swift Testing), which leaves a window in which edits go unseen.

## Decision

Tests always run in the real project, never in a copy. Every validate run has a start point and a finish point, and the core alone takes both:

```text
start point    note every route fingerprint (start.json); delete the selected reports
               ... the tests run: started by --run, or by you ...
finish point   read the reports; judge; fingerprint every route again
               changed since start?  -> no verdict: "code changed during the run"
```

- A report is trusted because it did not exist at the start point.
- A verdict is kept because the code its route depends on is the same at the finish point as at the start point.
- No timestamp, from the report or the file system, decides anything.

## Consequences

- Good: build caches and incremental builds work as normal. Measured, `validate --run` took 1.75–1.93 s, against 1.45–1.60 s for plain `swift test`.
- Good: one guard, the same for tests the core starts and tests you start, and it works with tools that record no time at all.
- Good: the guard is as precise as freshness. An edit to one marked region rejects only the use cases linked to it (the acceptance test edits one function; one use case loses its verdict, the others in the same file keep theirs).
- Cost: the guard compares two moments. An edit made after the start point and reverted before the finish point is not seen, so the verdict is stored against code the tests may not have run on. A frozen copy would close this; it was rejected for the cost below.
- Cost: running your own tests needs one extra step, `use-cases validate --start`, before them.
- Cost: when several started runs are open, `--finish` must name one (ADR 016).
- Cost: two `--run` requests at once may disturb each other's build state. The guard still withholds affected verdicts.

## Considered Options

- **A frozen copy per run:** airtight, but the tool rebuilt in every copy. Measured 4.1 s against 1.4 s in place, on a tiny package.
- **Trust the report's own start time:** no extra step, but Maven and cargo record none, and a start time taken after the build misses edits made during it.
- **Compare file modification times with the report:** clocks and copies make mtimes unreliable, and they cannot prove a report is new.
- **Trust reports as they are:** fast, but an old report could verify new code.

## Confirmation

These acceptance tests pin the rule:
- `test_linked_code_edited_during_the_run_gives_no_verdict` and `test_code_changed_during_the_run_gives_no_verdict` (the guard, for `--run` and for your own run)
- `test_an_unlinked_edit_during_the_run_keeps_every_verdict` (the guard is no wider than freshness)
- only new reports are read: now confirmed by ADR 020's checks
- `test_tests_you_ran_yourself_between_start_and_finish`, in all nine fixture repos

## Related Links

- `docs/design/13-verify-flow.md`
- `docs/design/12-results-storage.md` (the start stamp)
- `docs/design/11-fingerprints-and-freshness.md` (when fingerprints are taken)
