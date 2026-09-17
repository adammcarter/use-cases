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

**More than half the matrix has nothing mechanical behind it** — but the 47 are
two different problems, and an earlier draft of this section wrongly described
them as one:

| of the 89 active rows | |
|---|---|
| a `verifiers:` block defining what runs | 42 |
| **honest observation**: `required_verifiers: [agent]` or `[user]` | 17 |
| **defect**: `required_verifiers: [script]`, no `verifiers:` block defining it | 22 |
| **defect**: no verifier and no requirement at all | 8 |

`agent` and `user` are verifier KINDS, not ids a `verifiers:` block defines: an
agent observation or a person's sign-off has no command behind it by design.
Counting those 17 as broken would bury the 22 that really are.

**Row 2's target is 30** — the two defect rows. That number is now printed by
`scripts/check-scenario-conventions.mjs` beside row 1b's, so it starts with a
target rather than a surprise.

The 22 are a dangling reference. They name a verifier id that nothing defines,
and they read exactly like a healthy row — `uc matrix validate` passes them with
zero diagnostics, the same way it passed the dead `source_refs`. They are not a
decision to take; they are a bug to fix, and row 2 fixes it by defining the
verifier when it writes the test.

`scripts/check-scenario-conventions.mjs` now counts both shapes, so the number
gating row 2 is as countable as the number gating row 1b.

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

**Resolved: a missing verifier does not block the scenario.** A scenario says
what the behaviour IS; a `verification_policy` says how it gets proven. ADR 0007
puts them in different ladder rows — decision 1 is the scenarios, decision 2 is
the test and the binding — so the verifier is row 2's output, not row 1b's
precondition. `verification_policy` is row content, not contract: decision 8
freezes the envelope, the schemas, the marker syntax and the ledger formats, and
changing how an EXISTING behaviour is proven falls under rows for existing
behaviour being pre-approved.

The test to apply per row is one question: **is there a command or MCP tool
whose JSON the outcome can be asserted against?** For roughly 40 of the 47 the
answer is yes — `uc matrix validate`, `uc plan showcase`, the showcase command
family, `uc migrate test-matrix`, the MCP tools directly, `uc capsule list/plan/run`.
Those are deepened now.

**What genuinely blocks is eight rows**, and it needs a decision rather than a
judgement call:

- the five `lifecycle.loop.*` rows — agent doctrine, which no command implements
- `evidence.ledger.untrusted_content_boundary` — the same, a rule about how an
  agent must treat content
- `matrix.product.claim_guardrails` — the same
- `showcase.live.user_signoff` — proof that is genuinely a person, and an agent
  minting it is the thing the design exists to prevent

Decision 2 cannot cover these as written. Either they park like the 15 parked
`roadmap.*` rows, or decision 2 takes a named exception for doctrine. Until
that is answered they are left untouched rather than deepened, because
scenarios nothing can assert are padding, and padding reads as coverage.

## 7 · What row 2 actually has left, measured

Measured 2026-09-17, and it corrected a count I had been reporting wrongly for
several commits. My progress tally asked "does this row's verifier point into
`tests/blackbox/`?", which under-reports: a row is black-box if the tests it
names import no product internals, wherever they live.

| of the 98 active rows | |
|---|---|
| already black-box, in `tests/blackbox/` | 34 |
| **already black-box, elsewhere** | 16 |
| genuinely still white-box | 14 |
| no runnable verifier at all | 34 |

The 16 matter: `plugin/init`, `plugin/install`, `signing/tier`,
`plugin.bundle.runs_from_clean_clone` and `evidence.ledger.crash_durable_ledger_writes`
are already proven by tests that spawn the binary and import nothing. Rewriting
them would have been churn. They need at most a decision about whether to move
the files under `tests/blackbox/`, not new tests.

So the remaining work is **14 conversions and 34 rows needing a verifier**, not
the 36 conversions the old tally implied.

The check to use, rather than the file path:

```bash
grep -L 'from "\(\.\./\)\+packages/' <the test files a row's verifier names>
```

A row whose every named test file survives that grep is already an oracle row.

## 8 · The rows that need an owner decision

Three kinds, all parked rather than papered over. None has a passing test written
around it; each is a `test.todo` in the oracle carrying its reason, so nothing
reads as covered when it is not.

### a. Eight doctrine rows — no command implements them

The five `lifecycle.loop.*` rows, `evidence.ledger.untrusted_content_boundary`,
`matrix.product.claim_guardrails`, and `showcase.live.user_signoff`. These
describe how an AGENT should behave, or end in a person's judgement. There is no
`uc` command whose output could prove them, so ADR 0007 decision 2 cannot cover
them as written.

**The question:** park them like the 15 `roadmap.*` rows, or give decision 2 a
named exception for doctrine? Agreed 2026-09-17 to settle this at the end rather
than mid-ladder.

### b. Two rows asserting behaviour the tool does not have

Found while writing their oracles. Both are matrix-versus-product discrepancies,
not test bugs, and correcting either is a behaviour decision:

| row | what it claims | what was measured |
|---|---|---|
| `agents.roster.shipped_with_plugin` | "the published package files list includes agents" | `package.json` has no `files` key; it is `private`, and npm distribution was removed in 0.7.0 |
| `skills.assets.unreachable_skills_fail_doctor` | a manifest declaring a directory that does not hold the canonical skills "does not count as declared" | pointing the `skills` key at a nonexistent directory still reports `ok: true`, `declares_skill_root: true`, zero diagnostics — skills are found by CONVENTION at `skills/<name>/SKILL.md`, so the key is not what makes them reachable |

### c. Scenarios no test can drive

`plugin.install.claude_from_github.edge_live_session` and the other host
live-session scenarios need a real host session and a person watching.
`diagnostics.contracts.missing_build_hint` fires on the path where the compiled
core is absent, which the self-contained bundle never takes; it stays on its
white-box verifier until the Swift cut-over gives it an equivalent.

These are not failures of the oracle. They are the honest edge of what a
black-box suite can claim, and naming them is what keeps the coverage number
meaning something.

## 9 · Facts about the tool, measured — including one I got wrong

Written while converting rows with parallel agents. Each of these cost a cycle
somewhere, so they are recorded rather than rediscovered.

### The one I got wrong and propagated

I claimed, in three separate agent briefs, that a row needs a real
`verification_policy` to be selectable for a plan, and that `mode: none` yields
an empty selection. **That is false.** Measured: a `mode: none` row reports
`candidate_summary: {considered: 1, eligible: 1, selected: 1, excluded: 0}` and
`showcase start --adhoc` gives it a proper plan item.

The real gate is `hardEligibilityExclusion` in
`packages/core/src/presentation/candidates.ts`: `lifecycle === "active"`, a
host-surface match, and non-empty resolved steps and expected observations.
Verification policy affects the item's `verification_state` AFTERWARDS, never
whether it is selected. An agent caught this by probing rather than trusting the
brief, which is the behaviour to keep.

### Fixture traps

- `use_cases: []` fails `schema.minItems`; the matrix then reads `unusable` and
  every downstream assertion measures that instead of the behaviour. Always seed
  one complete active row.
- Skills fixtures must copy the REAL plugin layout. A hand-built minimal one
  reports `skills.missing` even when intact.
- Overwriting a bound source file deletes the `@use-case:` markers `bind`
  inserted, silently unbinding the row. Edit inside the span instead.
- A dry-run plan reports `disposition: "run"` even for a command that does not
  exist — the plan does not stat the binary. `blocked` means no verifier
  RESOLVES, e.g. `required_verifiers` naming an id nothing defines.

### Shapes worth knowing

- Diagnostics live at the envelope TOP level. On a refusal `data` is `{}`.
- The envelope's `command` is namespaced by its module: the CLI word `impact`
  reports as `markers.impact`.
- `matrix list --json` projects `{id, title, feature_id, lifecycle, value_tier,
  journey_role, source_path, semantic_hash, host_surfaces, tags}` — NOT
  `usage_frequency`, and not scenarios.
- Evidence aggregates carry `freshness_inputs` (the row hashes the evidence was
  taken against), not a computed `freshness` state. Staleness is visible by
  comparing those with the row's current `semantic_hash`.
- MCP write gating is TWO locks with distinct codes:
  `mcp.server_write_mode_required` (session) and `mcp.write_mode_required`
  (call).

### Two further product discrepancies found by agents

| what a row claims | what was measured |
|---|---|
| `migration.importer` — an import "cannot produce an active row" and rows "stay draft or planned until a human reviews" | a legacy row with both a `Scenario` and an `Expected` column lands `lifecycle: active` on `--write`, with zero evidence and no warning. `testMatrix.ts:280` sets it from `clearBehavior = Boolean(scenario && expected)`, ignoring the legacy status entirely. Mitigated: the row still scans UNBOUND and the acceptance claim stays NOT_SUPPORTED. |
| `planning.cards.audience_timebox_fit` — exclusions explain themselves | a timebox-forced exclusion is always reported with `reason_code: "max_items"` and the item-cap wording. `selectPlan.ts:68` passes `"max_items"` unconditionally, so the `timebox` branch in `exclusionFor` is unreachable. |

Both are behaviour decisions, so the affected scenarios assert only what is true
and name the gap rather than passing on a false premise.

## 10 · A bucket (c) found: real behaviour with no CLI affordance

Section 3 says a bucket (c) — a behaviour that would need a NEW command or flag
to be observable — stops the ladder, because a new affordance is a contract
change under ADR 0007 decision 8. One has now been found.

**`showcase.flow.revision_epoch_staleness`.** The row says that resuming a
paused run across a revision change marks the affected verdicts stale. The core
implements exactly that: `appendShowcaseEpoch` in
`packages/core/src/showcase/appendShowcaseEvent.ts` writes the epoch event, and
`replayRun.ts` handles `epoch_started` by setting
`item_currency: "stale_due_to_epoch_change"`.

**No CLI command ever calls it.** `uc showcase resume` accepts only
`--run/--reason/--actor/--idempotency-key/--recorded-at` — no changed-path, no
revision snapshot — and its handler calls `resumeShowcaseRun` alone. Searching
the whole CLI package for "epoch" returns nothing.

So the behaviour is real, implemented, and unobservable from outside. Its three
scenarios are `test.todo` and the row is deliberately NOT bound: binding it
would mark it verified against an oracle that asserts nothing.

**The decision this needs:** either the CLI gains a way to supply a revision
snapshot on resume — which is a new affordance, so it stops for the owner — or
the row is rewritten to describe only what is reachable, which is retiring
behaviour and also the owner's call.

Two rows are now deliberately unbound for the same reason, and both say so where
the marker pair would otherwise be:

| row | why it is unbound |
|---|---|
| `showcase.flow.revision_epoch_staleness` | the epoch machinery has no CLI entry point |
| `migration.importer.human_review_activation` | there is no CLI review/printout/activate step at all; `migrate test-matrix` offers only `--dry-run` and `--write` |

An unbound row with an honest `test.todo` is better than a bound row with a
vacuous oracle. The first leaves the coverage number truthful; the second
inflates it.
