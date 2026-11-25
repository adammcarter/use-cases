# ADR 004: Every validation link needs a result

## Status

Accepted - 2026-09-25

## Context

The most dangerous failure is a false pass: a check reported as verified when its test never ran. With exit codes alone this is easy to hit. Swift Testing exits 0 when a filter matches nothing (measured).

## Decision

- **Didn't run is never a pass.** A route with a validation link that received no result gets no verdict, with the diagnostic "its test didn't run".
- **A fail beats "didn't run".** If any link of the route failed, the route is `failed`, because the behaviour is already known to be broken.
- **Worst wins** otherwise: `fail` > `error` > `incomplete` > `pass`.
- Implementation links and resources never expect results.

## Consequences

- Good: a command that runs nothing can never verify anything.
- Good: a failure is never hidden behind a gap somewhere else.
- Cost: a route stays unverified until every one of its validation links has a result in the same run. That can be across several run commands, whose results are merged first.
- Cost: tests a transformer can't see stay unverified, not verified. For example, XCTest tests are absent from Swift Testing's report (verified), so the `swift-testing` transformer leaves them unverified; `swift-test` reads the console as well to cover them.

## Considered Options

- **Trust the exit code:** simple, and it gives the false pass above.
- **Ignore links with no result:** a partly-run route would still verify.
- **"Didn't run" beats a fail:** hides a known breakage behind a missing result.

## Confirmation

Across nine fixture repos (eight languages plus Cucumber), a filtered run never verifies the use cases whose tests it skipped: `test_a_filtered_run_never_verifies_what_it_skipped` fails in all nine when the rule is removed. `test_a_fail_beats_a_test_that_did_not_run` fails when a fail no longer beats "didn't run".

These acceptance tests also pin the rule:
- `test_the_old_false_pass_cannot_happen`
- `test_a_marked_test_the_command_skips_is_never_a_pass`
- `test_a_build_break_gives_no_verdicts_and_one_run_error`

## Related Links

- `docs/design/07-verification-state-model.md`
- `docs/design/13-verify-flow.md`
