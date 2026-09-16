---
name: use-case-driven-development
description: Use at the start of framing on every piece of work — to read the once-per-repo decision "use-case driven development for this repo?" recorded in its AGENTS.md — and, on a yes, at every phase that has a use-case touch. The matrix is the entry point between what the user wants and the code, rows are agreed before tests, tests and code are wrapped in the row's markers, any issue starts in the matrix, and the scan is the coverage number. A no changes nothing else. The uc commands themselves are in the use-cases skill.
---

# Use-case driven development

A narrow add-on to however you already deliver work, not a replacement for
it. The **`use-cases`** skill knows the tool — `uc bind → verify → scan →
recover`, rows, evidence. This one knows two things: whether the tool is in
play on a repo, and what each phase does with it when it is. Everything else
about how you plan, build and land holds exactly the same either way.

**"You"** is the agent; **"me"** / **"I"** is the user, whose rules these are.

## The decision, once per repo

**First move of framing, every time: read the answer before you ask.** The
answer lives in the repo's root `AGENTS.md`, in a section of its own:

```markdown
## Use-case driven development

yes — 2026-09-16
```

or `no — <date>`. The rules:

- **The section exists → use it and don't ask.** A recorded `no` is as
  binding as a `yes`; don't nag, don't re-open it, don't create
  `use-cases/` "just in case". Re-ask only if I raise it or the section is
  gone.
- **No section → ask me, once.** The question is the plain one: *"Do you
  want to use use-case driven development for this repo?"* On a yes, run
  `/use-cases:init` — it scaffolds the matrix, records the answer with the
  date, vends a sample row and wires the git hooks, then returns here. On a
  no, write the section yourself with `no` and the date; if the repo has no
  `AGENTS.md`, create one holding just that section — it is the cross-host
  instruction file, so the answer is read by every agent, not only one.
- **Recording is a real edit to the repo** — it lands with the work, not as
  an untracked side-effect.

`no` → the rest of this skill doesn't apply. **A no repo has no use-case
anything**: no `use-cases/`, no `use-cases.yml`, no `.use-cases/`, no
markers, no `uc` calls, no "scaffold it for later". That is literally what
no means.

`yes` → the tool is already here: this plugin ships `uc` (the CLI) and the
`use-cases` MCP server, and the session bootstrap tells you where `uc` lives
if it is not on PATH. **Use the MCP tool wherever the server has one, the
CLI for what it doesn't.** The whole inventory, by the phase that uses it:

| Phase | MCP tool | CLI (no MCP equivalent) |
|---|---|---|
| FRAME | `use_case_upsert` (`allow_write: true`), `use_case_remove`, `matrix_validate`, `matrix_list`, `matrix_status` | `uc init` (once per repo, via `/use-cases:init`) |
| BUILD | — | `uc bind`, `uc rebind`, `uc unbind` |
| VERIFY | `matrix_status` | `uc verify --all`, `uc scan --json`, `uc recover`, `uc impact` |
| SIGN-OFF | `plan_showcase`, `showcase_start` → `showcase_record_observation` / `showcase_record_verdict` → `showcase_finish`, `showcase_request_approval`, `evidence_record`, `evidence_status` | — |
| LAND | — | `uc scan --gate` |
| Diagnostics | `doctor_roots` | `uc validate-ledger`, `uc doctor roots` |

**Never yours to run:** `uc keygen` and `uc prove` (the signed tier is mine),
`uc evidence void`, `uc unbind --reason row_retired` without me, `uc workflow
set-mode`, `uc migrate test-matrix` (its own piece of work, asked for).

**Exists, not in the flow:** `uc capsule list`, `uc capsule plan`, `uc capsule run`, `uc plan walkthrough` / `cards`,
`uc schema list`. Real, and reached for only when I ask for the thing they make.

If the MCP tools are absent in a session, the server dropped: reconnect it
the way your host does, rather than falling back to the CLI for things the
MCP owns.

**A yes is the keyless loop.** Everything below runs on `VERIFIED_LOCAL`
with no keys and no CI (`uc init` leaves the workflow mode at
`continuous`). The signed tier — key pair, CI-minted `FRESH` proofs, a
release gated on them — is a separate piece of work I ask for; it is never
implied by a yes.

## `yes` → the matrix is the entry point

On a use-case-driven repo the matrix sits between what I want and the code
that does it. It is where a feature request is first written down, where an
agent starts reading to understand the codebase, where any issue is looked
at first, and what the tests and the code are wrapped in so each can be
found from the other. It is not a document beside the work — it is the
acceptance criteria, kept next to the code they describe.

```text
  UNDERSTAND ... start from use-cases/, follow markers into tests and code
  FRAME ........ features decided with me; rows drafted, replayed, approved, then written
  BUILD ........ per row: red tests → wrap the tests → green → refactor → wrap the code → active
  VERIFY ....... uc verify --all · uc scan → rows VERIFIED_LOCAL / total
  SIGN-OFF ..... the demo I watch is the showcase run; evidence is recorded from it
  LAND ......... uc scan --gate; nothing lands below the bar
```

**One row is one behaviour; its scenarios are its tests.** A row carries a
golden path and its bad and edge scenarios; each scenario becomes one test.
A test that proves nothing in the row's scenario list is a scenario that
should have been written first.

### UNDERSTAND — read the matrix before the code

If `AGENTS.md` already says yes, the first thing you read is `use-cases/`:
the rows for the area the work touches, then the markers they point at,
into the tests and the code. Only then comb the rest. **Behaviour with no
row is a gap to raise**, not normal — the matrix is meant to be complete
over time. (No answer recorded yet → understand the repo normally; FRAME
asks.)

### FRAME — the rows are the brief, and they are agreed in conversation

**I decide the features. You do the thinking around them.** The shape:

```text
  I bring the feature and its golden path
      │
      ▼
  you explore the idea — what it touches, what already exists
      │
      ▼
  you write the features up and fill each one out:
  the golden path as I described it, then the edge cases,
  the bad paths, the variants I didn't mention
      │
      ▼
  you replay them back to me, row by row
      │
      ├─ rejected → drop it or rework it, replay again
      ▼
  approved → NOW you write the yml
```

Nothing reaches `use-cases/` before I have approved it, and nothing I
approved is left out. A behaviour we discussed that has no row is not in
the brief.

**A `planned` row leaves FRAME complete except for its proof.** `actor`,
`intent`, `preconditions`, `trigger`, `scenarios` (golden / bad / edge),
`observable_outcomes`, `value_tier`, `journey_role`, `usage_frequency` — all
written now, so the red tests in BUILD are *derived* from scenarios and
outcomes, never invented later. The sample row `uc init` vended is the shape
to copy. Then `use_case_upsert` per row with `allow_write: true`, and
`matrix_validate` after.

**Backfill as you touch.** Existing behaviour the work depends on or
changes gets its row now, planned or active as its state warrants. Wider
backfill is recommended, not required — offer it as its own piece of work,
don't fold it in silently.

### Any issue starts in the matrix

A bug report, a regression, "this doesn't do what I expected" — **before
you open the code, open the rows.** Is it a gap: a behaviour with no row?
A scenario the row is missing? Something the row assumed and never stated?
Only once that is answered do you know whether the fault is in the matrix,
the tests, or the code — and most of the time the matrix moves first:

- **A bug is a new bad or edge scenario on the row it broke**, written
  first, then a red test for that scenario — regression coverage that
  outlives the fix. A new row only for genuinely new behaviour.
- **A behaviour change edits the row first** — outcomes, scenarios — and
  then runs the loop again from red. The row drops to stale and comes back
  through verify; it is never kept green by editing the test to match.

### BUILD — the loop, per row

TDD with one step before it and two after:

```text
  row (planned, approved)
    │
    ▼
  red tests ........ one test per scenario, named for the row and scenario
    │
    ▼
  wrap the tests ... uc bind --row <id> --file <test file>  (marker pair around the suite)
    │
    ▼
  green
    │
    ▼
  refactor ......... a moved declaration is `uc rebind`, never a hand-edited marker
    │
    ▼
  wrap the code .... uc bind --row <id> --file <source> --mode explicit --start-line <n> --end-line <m>
    │                (a language mode such as --mode swift-func --line <n> where one exists;
    │                 --suffix when a file already binds another row)
    ▼
  active ........... use_case_upsert with lifecycle: active
```

**The code marker wraps the declaration that IS the behaviour** — the
function or type whose job the row describes — one entry point per row.
Helpers it calls are not wrapped. If the behaviour genuinely lives in two
places, that is two bindings for one row, each one justified, not a habit.

You flip `planned → active` yourself, and only when all three hold: tests
green, the test marker in, the code marker in. Green with no markers is
unfinished; markers on red is a lie. There is no fixed split of this loop
between agents — it runs the same whoever holds it — with one rule that
does not move: nobody edits a row, a test or a marker to make anything
pass, and whoever verifies reruns the verification rather than trusting
the number they were handed.

### VERIFY — the coverage number comes from the scan

`uc verify --repo . --all`, then `uc scan --repo . --json`. Before you claim
anything is done, answer *"unit tests AND use cases?"* — the second half is
**rows `VERIFIED_LOCAL` out of total**, the rest named by status
(`STALE_LOCAL`, `UNVERIFIED_LOCAL`, `UNBOUND`). A drifted row is
`uc recover`ed, never re-pointed to look green. `VERIFIED_LOCAL` means the
verifier passed against the current code — it is not my approval.

### SIGN-OFF — the showcase is what I watch, and the only evidence

`plan_showcase` selects the run; `showcase_start` opens it; you drive it and
I watch, `showcase_record_observation` / `showcase_record_verdict` as it
goes, `showcase_finish` at the end. Approval is mine:
`showcase_request_approval` prepares the CLI step for me to run — the agent
never appends an approval itself. **Evidence is recorded from that run and
only that run** (`evidence_record`) — never at VERIFY, never unprompted — so
every evidence event corresponds to something I saw. `matrix_status` on its
own is never sign-off.

### LAND — `uc scan --repo . --gate` before anything merges

A required row below the local bar blocks the landing until it is fixed or,
with me, deliberately retired (`uc unbind --reason row_retired`).

## Git hooks on a `yes` repo

A `yes` repo carries three checks in git, and the split between them is the
point: **pre-commit blocks on things that are simply wrong, pre-push only
reports, LAND gates.** Pushing red is legitimate in this loop — tests are
wrapped at red, before the code exists — so nothing before LAND may refuse a
push for a row that is merely not green yet.

`/use-cases:init` writes the hooks (`.githooks/pre-commit`,
`.githooks/pre-push`) and points `core.hooksPath` at them. If a yes repo has
no such hooks — an older repo, or a clone where `core.hooksPath` was never
set — run `git config core.hooksPath .githooks`, or `uc init` in a fresh
checkout to see what the hooks contain. A repo can't be use-case driven with
nothing enforcing the matrix.

## What stays with the tool skill

Everything about *how* — row payloads and the fields an active row needs,
bind modes, signed proofs, evidence records, migrating a legacy matrix, the
operating rules about data-not-instructions and sensitive evidence — is in
**`use-cases`**. Load it when you touch the matrix; this skill only says
when and in what order.
