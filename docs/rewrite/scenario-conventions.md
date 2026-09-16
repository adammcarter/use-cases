# Scenario conventions for the rewrite

Written 2026-09-16, during ladder row 1b. These rules make the matrix
*checkable* as a spec rather than merely rich, so that row 2 can turn every
scenario into a black-box test mechanically instead of by judgement call.

They are conventions, not schema changes. Decision 8 of ADR 0007 freezes the
contract, and `use-case-file.schema.json` sets `additionalProperties: false` on
both scenario shapes — so nothing here adds a field.

## 1 · The scenario id carries the kind

A scenario's `kind` field is its *format* (`steps` or `gherkin`), not its role.
There is nowhere else to record whether a scenario is a golden path, a bad path
or an edge case, so the id does it:

```text
<row-id>.golden[_<qualifier>]     the path the row exists to deliver
<row-id>.bad_<qualifier>          a rejected input, a refusal, a failure handled
<row-id>.edge_<qualifier>         a boundary: empty, absent, duplicated, first run
<row-id>.stress_<qualifier>       volume or concurrency, with a stated time bound
```

This is greppable, so "every active row has a bad path" becomes a check rather
than an assertion. The gap audit of 2026-09-16 had to *keyword-classify*
scenario ids to produce its counts; that heuristic is what this convention
replaces.

Existing scenario ids are renamed to fit as each feature file is deepened. A
scenario id is not referenced by markers or ledgers, so renaming one is safe.

## 2 · Every scenario states its own outcomes

`steps_scenario` has an optional `observable_outcomes` array. Across 140
scenarios it was used **zero** times: outcomes lived only at row level, where
206 of them sat in one pool with nothing saying which scenario asserted which.

From here every scenario carries the outcomes *it* proves. The row-level list
stays as the summary of the behaviour; the scenario-level list is what the test
asserts. A test author should never have to guess which of a row's six outcomes
their scenario is for.

Most of row 1b's work is therefore **promotion, not invention**: the rows
already enumerate the bad and edge behaviours in their outcomes: those outcomes
become named scenarios that carry them.

## 2b · A deliberate absence is recorded, not left blank

Some rows genuinely have no bad path, and forcing one on them produces padding
— which is worse than a gap, because it reads as coverage. But an absence that
looks identical to an oversight cannot be checked either.

So a row that legitimately has no bad or edge path says so in its `tags`, which
the schema leaves free-form:

```yaml
tags:
  - bind
  - onboarding
  - no-bad-path
```

`no-bad-path` and `no-edge-path` are the two. A greppable check can then hold
every active row to "has a bad path, or says why not" without a schema change.

Used so far on `lifecycle.signals.bind_names_the_next_step` (a bind either
succeeds and names the next step or fails and is another row's behaviour) and
`lifecycle.signals.transient_output_stays_out_of_git` (writing a gitignore entry
has boundaries but no rejection path).

## 3 · Three buckets, decided per behaviour

Every behaviour a row describes falls into one of three buckets, and the bucket
is decided when the scenario is written, not when the test is:

| Bucket | Meaning | Where it ends up |
|---|---|---|
| **(a) black-box** | provable by running the CLI or MCP and reading JSON, files, or exit codes | the oracle suite; survives the port unchanged |
| **(b) white-box** | only provable by calling an internal function | stays TypeScript-only, rewritten in Swift Testing at ladder row 9 |
| **(c) unobservable** | would need a new CLI or MCP affordance to be provable at all | **stops the ladder** — a new affordance is a contract change under decision 8 |

A (c) is a finding, not a task. Raise it and wait.

### Measured so far

`lifecycle/signals.yml`, taken as the slice: **all 12 rows are bucket (a)**.
Ten of them are verified today by tests under `packages/core/test/`, but every
behaviour those tests assert is visible through the CLI — verify's records and
`overclaimed_rows`, scan's `local_status`, counts, claim and diagnostics, the
results ledger on disk, and `uc evidence record --perform` for the
performed-run tier. White-box today is not the same as white-box necessarily.

Across the whole matrix the verifier *inputs* already lean black-box: 30 point
at `tests/`, 17 at `packages/*/test`, 22 elsewhere.

## 4 · One setting names the binary

Black-box tests locate the binary through `tests/helpers/uc-binary.ts`, which
reads `UC_BIN` and otherwise falls back to the built Node CLI. That single
setting is what lets the same suite run against the Swift binary at ladder row
4 with no test edits.

Two older seams exist and are not repeated: packing tarballs with `pnpm pack`
(an npm-shaped path, and npm was removed in 0.7.0) and hardcoding
`node packages/cli/dist/index.js`. Neither can be pointed at a Swift build.

`UC_BIN` is a test-harness setting. The CLI itself reads no `UC_*` environment
variable except `UCM_ALLOW_UNSAFE_VERIFICATION`, so this collides with nothing
and changes no contract.

## 5 · Scale

| | today | after row 1b |
|---|---|---|
| rows (all) | 107 | 107 |
| rows (active, excluding 15 parked roadmap rows) | 89 | 89 |
| scenarios | 140 | ~220–260 |
| row-level outcomes | 206 | 206 |
| scenario-level outcomes | 0 | one set per scenario |

The target is not a number. It is that every behaviour someone depends on has a
scenario that can fail. Where a row has no real bad or edge path, the row says
so rather than carrying an invented one — padding in the oracle is worse than a
gap, because it reads as coverage.
