# ADR 019: Four statuses with fixed meanings; reports are private copies that never hold code

## Status

Accepted - 2026-09-25

Its report handling is superseded by [ADR 020](020-each-run-owns-its-reports.md): each run owns its reports, and nothing is deleted.

## Context

The core judges, but it can only judge what transformers report. An audit showed the bundled transformers disagreed about what each status meant:

- A test retried until it passed was `pass` from one transformer and `fail` from another.
- An expected failure (pytest xfail, a Swift known issue) was `incomplete` from one and `pass` from another.

Once transformers ship, any later rule would need all of them changed, which ADR 015 forbids. The audit also found two unsafe gaps in the report handling:

- **A report path could name source code.** `--start` deletes the old report, so `report: Tests` deleted the tests.
- **Transformers read the live report**, while the core sealed a copy, so the bytes judged and the bytes stored could differ.

## Decision

- There are exactly four statuses, forever:
  - `pass`: the final attempt passed.
  - `fail`: the final attempt failed.
  - `error`: the test itself broke.
  - `incomplete`: the behaviour wasn't shown to work. This covers skipped, expected failure, pending and undefined.
- Each retry of a test counts by its final attempt. There is no retry flag and no attempt count. Use cases record that a behaviour is validated, not how. The test tool's own report, kept byte-exact in the run's `outputs/`, is where retries, timings and reasons live. `message` may carry a short note for people and never changes the status.
- A transformer is given a private copy of the report, outside `.use-cases/`. The core seals the same bytes. The copy's location means nothing.
- A report may not contain its own `working_dir`, another validation's report, or a root settings file. Before anything is deleted, `--start` and `--run` refuse a report that holds linked code, a resource, a use case file or a scope.

## Consequences

- Good: any transformer's `pass` means one thing, and the core stays a record of validation, not a second bookkeeping of what the test runner already reports.
- Good: deleting a report can never delete code, and the judged report is exactly the stored report.
- Cost: a test that passed only on retry counts as `pass`. Teams that want flakiness to block configure that in their test tool (fewer or no retries), where the retry happens.
- Cost: copying a very large report takes time and disk. It is done once per run.

## Considered Options

- **A fifth status, `skipped`:** more expressive, but an old core would reject it, and the reason a test was skipped is the test tool's to report.
- **A `retried` flag on results:** keeps a flaky-test policy open, but turns use cases into bookkeeping of test-runner detail. Rejected by the owner: "we should keep use cases as validated, not a bookkeeping to replace the tests runners themselves - we just know they pass, the original tests house the real information on how/why they passed".
- **Worst-of-all-attempts for retries:** stricter, but it contradicts what every test tool itself reports.

## Confirmation

- `test_transformers.py` covers retries in both orders, a Surefire flaky pass, a pytest xfail, a skip, and Swift known issues.
- The report rules are now confirmed by ADR 020's checks.

## Related Links

- `docs/design/10-bridge-settings-and-transformers.md` §7, §13
- ADRs 003, 015
