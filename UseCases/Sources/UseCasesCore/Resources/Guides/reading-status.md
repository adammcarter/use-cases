# Reading status

Each state a use case can be in, what "stale" means, which states block the gate, and what to do about each.

## The list

```text
$ use-cases status
✗ failed      basket.discounts         unit-tests failed (run 01a2057f via unit-tests)
· draft       example.getting-started  missing: value_tier

2 use cases · 1 failed · 1 draft
results: 4 runs · 1.3 MB
→ use-cases status basket.discounts   to see why
```

One line per use case, worst first: failed, error, incomplete, unverified, stale, verified, then drafts. Each has a symbol and a word, and a short reason beside anything not verified. The `results:` line is the results store (see below). The last line, after `→`, is the command you most likely want next; `--quiet` leaves it out.

## The results store

Every run keeps a folder in `.use-cases/`, and nothing is deleted on its own, so the store grows. The `results:` line under the list says how many runs it holds and how big it is. When a later run has said everything an older run says, the older run is superseded, and the line counts it:

```text
results: 12 runs · 450 MB · 7 superseded
→ use-cases prune   to remove 7 superseded runs
```

`use-cases prune` removes the superseded runs; `use-cases prune --dry-run` lists them and removes nothing. It changes no status, no count, no gate answer and no reason in the list. It keeps every run status reads for the code as it is now. What goes is old history, and the verdict for an older state the code later goes back to: that use case reads `stale` until it runs again.

## What each status means

| Status | Means | What to do |
|---|---|---|
| `✗ failed` | a test or a person said it does not work | fix the code (or the use case), then run again |
| `! error` | the test could not run properly | fix what stopped it, then run again |
| `◐ incomplete` | a test was skipped, or an expected failure | let it run for real |
| `○ unverified` | no verdict in this checkout yet | run the tests, or record a verdict |
| `~ stale` | it had a verdict, but something it depends on changed since | run again |
| `✓ verified` | proven, and nothing changed since | nothing |
| `· draft` | not fully written yet; never blocks | fill in what it says is missing |

A use case's status is the worst of its routes that gate. A route with `gates_verification: false` is shown, and never counts.

## When a verdict goes out of date

A verdict belongs to exactly what was proven. It goes `stale` when any of these change:

- the code inside an implementation marker or binding;
- the test inside a validation marker or binding;
- the use case's intent, the scenarios the route covers, or the route itself;
- a file listed in a route's `resources`.

These do not: the title, description, value tier or out of scope; how the tests are run (`use-cases-bridge.yml`); the comment text around a marker; moving marked code, unchanged, to another place. A `stale` route says since which run:

```text
~ stale       basket.discounts  unit-tests: changed since run 01a2057f
```

## One use case in detail

```text
$ use-cases status basket.discounts
~ stale  basket.discounts · Discounts never make a total negative

  route       gates   status          why
  unit-tests  yes     ~ stale         changed since run 01a20580
  try-it      yes     ~ stale         changed since run 01a20580

sign-off: changed since approved (by Sam on 2026-11-22)

→ use-cases verify --run
```

The "why" column names the run that decided each route, or what went wrong in it:

| Why | Means |
|---|---|
| `run 01a20580 via unit-tests` | decided by that run, through the `unit-tests` command |
| `run 01a20580 via record` | recorded by hand |
| `no verdict yet` | nothing has run for it in this checkout |
| `its test didn't run` | the run had no result for its marked test |
| `not linked: no validation links and no procedure` | nothing can prove it but `use-cases record` |
| `changed since run …` | proven once, changed since |
| `code changed during the run` | the code changed between `--start` and `--finish` |

A route proven by hand ("try it") is brought back with `use-cases record`, even when the hint says to run the tests.

## Only some use cases

| Command | Shows |
|---|---|
| `use-cases status basket` | the use cases under an id prefix |
| `use-cases status --group smoke` | the members of a group |
| `use-cases status --state failed,stale` | only those states (`draft` is one) |

An exact id always wins over a prefix. Filters combine.

## No verdicts in this checkout yet

```text
$ use-cases status
no verdicts in this checkout yet: 1 use case (1 draft), none run here
→ use-cases verify --run   for a baseline, if you want one
```

Verdicts are never carried between checkouts. Unverified here means nothing has run here, never that anything failed. A baseline run is optional, as running the tests after a clone is.

## Warnings under the list

- `its marked region is empty`: code moved and left its markers behind; move them with it.
- `run … never finished`: a run was started and neither finished nor aborted (`use-cases docs verifying`).
- `changed since approved`: the promise changed after its sign-off; approve it again once a person agrees.
- Group and marker warnings, such as a group whose prefix matches nothing.

## The gate

`use-cases status --gate` answers "does anything block?" and exits 1 when something does. `--strict`, for release branches, means everything must be proven:

| Status | Default | `--strict` |
|---|---|---|
| failed, error, stale | blocks | blocks |
| incomplete, unverified | warns | blocks |
| verified | passes | passes |
| draft | never blocks | never blocks |

```text
$ use-cases status --gate
○ unverified  basket.vouchers         unit-tests: no verdict yet   (warning)
○ unverified  basket.vouchers-expiry  unit-tests: not linked: no validation links and no procedure (run 01a20586)   (warning)
~ stale       basket.discounts        unit-tests: changed since run 01a20586 · changed since approved

gate: blocked · 1 block (1 stale) · 2 warnings (2 unverified)
→ use-cases status basket.discounts

$ use-cases status --gate --strict
○ unverified  basket.vouchers         unit-tests: no verdict yet
○ unverified  basket.vouchers-expiry  unit-tests: not linked: no validation links and no procedure (run 01a20586)
~ stale       basket.discounts        unit-tests: changed since run 01a20586 · changed since approved

gate (strict): blocked · 3 block (2 unverified, 1 stale)
→ use-cases status basket.vouchers
```

`--gate --group release` gates one group. `--gate` cannot be combined with an id or `--state`.

With `sign_off: required` in the root `use-cases.yml`, a READY use case whose promise is not approved as it reads now also counts: `critical` blocks, `core` and `supporting` warn, and `--strict` blocks all three.

## In JSON

`use-cases status --json` lists every use case with its `status`, `routes` (each with `status`, `gates`, `linked` and `note`), `approval` (`approved`, `changed` or `unapproved`) and, when READY, its `value_tier`. With `--gate`, `gate` holds `passed`, `strict`, `blocking` and `warning`. `store` holds the store's `runs`, `bytes` and `superseded`, when it has any run. Scripts read this, never the human lines.
