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

`UC_BIN` is a test-harness setting and collides with nothing, but an earlier
draft of this document (and commit 89cd1ee) claimed the CLI reads no `UC_*`
variable except `UCM_ALLOW_UNSAFE_VERIFICATION`. **That was wrong**, and it was
wrong because the grep that produced it piped through `grep -oE '"[A-Z_]{4,}"'`,
which only matches *quoted* tokens and so returned 70 diagnostic-code constants
and no environment variables at all.

What the source actually reads:

| variable | read by | what it does |
|---|---|---|
| `UC_RUN_KEY_FILE` | `markers/runAttestation.ts` | moves the machine-local run key off `~/.use-cases/run-key` |
| `UCM_ALLOW_UNSAFE_VERIFICATION` | `markers/cli/prove.ts` | permits an assumed verification result |
| `UCM_MCP_REPO` | `mcp/resources.ts` | the repo the MCP server serves |
| `UCM_MCP_WRITE` | `mcp/toolHandlers.ts` | enables write tools |
| `UCM_MCP_COMMAND_EXECUTION` | `mcp/toolHandlers.ts` | enables command execution |

`UC_RUN_KEY_FILE` matters to this work beyond the correction: it is what makes
the attestation scenarios testable at all. A black-box test points it at a
throwaway path, so the suite never reads or writes the developer's own key, and
`edge_scan_never_mints_a_key` can assert that no file appeared there.

## 5 · Scale

| | today | after row 1b |
|---|---|---|
| rows (all) | 107 | 107 |
| rows (active, excluding 15 parked roadmap rows) | 89 | 89 |
| scenarios | 140 | ~300–380 |
| row-level outcomes | 206 | 206 |
| scenario-level outcomes | 0 | one set per scenario |

That estimate is the slice's rate, not a guess: 12 rows produced 52 scenarios,
4.3 per row, and 89 active rows at that rate is roughly 380. Signals is richer
than average — 49 of the 206 row-level outcomes sit on 13% of the rows — so the
true figure is below it. An earlier draft said 220–260, which the slice showed
was low.

The target is not a number. It is that every behaviour someone depends on has a
scenario that can fail. Where a row has no real bad or edge path, the row says
so rather than carrying an invented one — padding in the oracle is worse than a
gap, because it reads as coverage.

## 6 · The observation-only half

Measured 2026-09-16, while ordering the remaining feature files:

| active rows | |
|---|---|
| with a `verifiers:` block, so something can actually run | 42 |
| with none — proven by `agent_observation` or `manual_observation` | 47 |

**More than half the matrix has nothing mechanical behind it.** Those rows
declare `required_verifiers: [agent]` or `[user]` and a `requirements` block,
but no command, so `uc verify` has nothing to spawn and the row can never reach
`VERIFIED_LOCAL` on its own evidence.

This matters because ADR 0007 decision 2 says every row is proven through the
binary before any Swift is written. Forty-seven rows cannot be, as written.

They are not one kind of thing, and the difference decides what row 1b does
with each:

- **Behaviour the CLI or MCP really does, that simply never got a verifier.**
  `matrix.core.validate`, `matrix.core.mutate`, `mcp.wrapper.parity`,
  `migration.importer.*`, `showcase.flow.*`, `planning.cards.*`,
  `capsule.demos.*`, `diagnostics.contracts.*`. Every one of these is a command
  with observable JSON. They can have golden/bad/edge scenarios AND a real
  verifier; the verifier is missing, not impossible.
- **Doctrine about how an agent should behave**, which no command implements.
  All five `lifecycle.loop.*` rows, and `lifecycle.loop.user_feature_printout`
  in particular, describe what an agent should do and when to ask the user.
  There is no binary behaviour to drive. Writing golden/bad/edge scenarios for
  them produces scenarios no test can assert — padding in the oracle, which
  reads as coverage and is worse than a gap.
- **Rows whose proof is genuinely a person.** `showcase.live.user_signoff` ends
  in a human approving. The tool's part is drivable; the approval is not, and
  must not be, since the whole point is that an agent cannot mint it.

The open question this raises is not a detail of wording: **does row 1b deepen
an observation-only row with scenarios nothing can assert, or does the missing
verifier get added first?** Adding one is not new behaviour — the behaviour
already exists and already has a command — but it does change how the row is
proven, which is row 2's subject rather than row 1b's.

Recorded here rather than decided alone.
