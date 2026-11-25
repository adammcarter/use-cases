# ADR 003: Helpers report one result per link; only the core judges

## Status

Accepted - 2026-09-25

## Context

Something must turn a test tool's output into use-case verdicts. If each tool integration decided verdicts itself, the honesty rules would be re-implemented, and possibly weakened, once per tool.

## Decision

A **results transformer** converts a test tool's report into one result per validation link: `pass`, `fail`, `error` or `incomplete`. It never gives a verdict for a whole route or use case.

The core alone applies every judgement:

```text
transformer reports what happened    core decides what it means
─────────────────────────────────    ──────────────────────────
"test at line 6 passed"              which link contains line 6?
"test at line 10 failed"             did every validation link get a result?
"line 35 passed, no link"            worst result wins; stale; code changed during the run
```

A test inside no link is reported as "test not tied to a use case". A transformer that crashes or breaks the contract is a run error, and never fails a route.

## Consequences

- Good: one test run gives every linked use case its verdict, whether it passes or fails. No re-runs are needed to find which test failed.
- Good: every transformer is held to the same rules, and a buggy one can't manufacture a pass.
- Good: transformers are easy to test. They have the same input and output every time, and can be checked against a saved report without the tool installed.
- Cost: the tool must produce a structured report with a location for each test. Tools that can't need an `exit-code`-style transformer, which gives one result per file.

## Considered Options

- **Transformers return route verdicts:** simpler to write, but every transformer would carry the judging rules.
- **The core reads reports directly:** no extra programs, but it ties the core to every tool's format (see ADR 010).

## Confirmation

In the acceptance tests, one run of a real Swift package gives verified, failed and incomplete verdicts. The Swift transformer is checked against a saved report with a hand-written expected result. Three broken-transformer cases (malformed output, an unknown link, a crash) each produce a run error and no failed route.

## Related Links

- `docs/design/10-bridge-settings-and-transformers.md`
- `docs/design/07-verification-state-model.md`
