# 21 — Agent Workflows

**Phase:** 4 — Agent Layer  
**Status:** Specification (locked)

## 1. Purpose

This chapter is the backbone of using Use Cases: how an agent works with a person, use case first, from a request to proven code. It is a harness. The person decides behaviour by reading use cases; the agent does the work, and every step leaves proof that a command can show.

Agents work test first by default: red, green, refactor. Use Cases is not a TDD tool, and the core never enforces it, but it is the way an agent is guided to work.

## 2. What good looks like

```text
 the person ─── speaks and reads USE CASES, never YAML or code, to decide behaviour
    │
    │  asked only when it matters:  intent (if thin) · sign-off · a showcase
    ▼
 the agent ──── works the flow, and every step leaves proof a command can show
    │
    ▼
 the repo ───── use cases stay the truth: new or years old, same flow, same layout
```

| Quality | Meaning |
|---|---|
| **One language** | the person approves behaviour by reading use cases, never code |
| **One layout** | every suggested use case looks the same, in every repo (section 7) |
| **Asked, not interrogated** | the agent asks at a few fixed moments and works in between |
| **Proof, not claims** | "done" means a command shows it: linked, verified, gated |
| **The person holds the line** | behaviour changes only with their sign-off; critical ones always |
| **Any size of repo** | a new repo finds nothing, an old one finds its map; the same steps |

## 3. The flow

`[F]` marks the four steps with a canonical format (section 7).

```text
 0 SETUP          once per repo: ASKS, then a small block in AGENTS.md
                                   │
 1 REQUEST  ◀──────────────────────┼───────────────────────────────┐
            a few words ··· a full spec ··· a spike's results      │
                                   │                               │
 2 INTENT   [F] WHAT and WHY: ask only if it's too thin            │
            (enough already? move straight on)                     │
                                   │                               │
 3 DISCOVER  use cases first: search / --like ─▶ links ─▶ tests    │
             then the codebase itself, as ever: not everything     │
             is covered by use cases; they're the starting point   │
                                   │                               │
            what kind of change?                                   │
   ┌──────────────┬────────────────┼──────────────────┐            │
   ▼              ▼                ▼                  ▼            │
 FAST PATH     EXPLORE        NEW OR CHANGED     NO BEHAVIOUR      │
 papercut,     unsure what    BEHAVIOUR          CHANGE            │
 tuning:       good looks     │                  refactor          │
 edit the use  like? spike    │                  │                 │
 case + test,  it: kept as    │                  │                 │
 one line to   short as it    │                  │                 │
 confirm       needs, proved, │                  │                 │
   │           then ──────────┼──────────────────┼─────────────────┘
   │           back to 1 with the results        │
   │                          ▼                  │
   │            4 BRIEF   [F] each new, changed or untouched use case:
   │                      golden, edges, out of scope, what it replaces
   │                          ▼                  │
   │            5 SIGN-OFF [F] the proposal: plain words, what you'll see,
   │                      choices + previews, ids last
   ▼                          ▼                  ▼
 6 TDD      red ─▶ can it fail? ─▶ green ─▶ refactor ─▶ still verified
            touched marked code or added a behaviour? say so ─▶ back to 4
                                   │
 7 SEE IT   user-visible? perform it the way the user will
            the owner tries it ── "change X" ──▶ back to 4 (the normal case)
                                   │
 8 PROVE    [F] the results ◀── CI: verify --run, then status --gate
```

## 4. Notes on the flow

- **Step 0 asks first.** AGENTS.md is shared with people and other tools. The block is added only when the person says yes; its markers let a later version replace it in place without touching anything around it. It belongs to the plugin's setup (chapter 22), not the core's `init`. It also asks whether to turn on the sign-off gate (section 6).
- **Enough already? Move on.** A request that already says what and why skips the questions at step 2; a spike's results usually do.
- **A fresh checkout needs no baseline.** Verdicts are like test results: each checkout gets its own by running, and none are carried over. Running `verify --run` first is the person's call, as running the tests after a clone is; the repo's CI may already guarantee them. The agent never runs one by default, and never reports "no verdicts here" as a finding: unverified means no verdict in this checkout, never failed.
- **Use cases are the starting point, not the only way in.** At step 3 the agent reads what exists through its use cases (use case, links, tests and docs, then the source), and then reads the codebase the usual way, because not everything is covered by use cases. Code no use case covers is worth mentioning, not fixing unasked.
- **Four routes out of discover:**
  - **Fast path:** a papercut or a tuning change ("4 s, not 40 s") edits the use case and its test, confirmed in one line. No brief.
  - **Explore:** when what good looks like is unclear (often visual or interaction work), a spike tries it out. It takes no longer than it needs, it is proved, and its results go back in at step 1 as a better request.
  - **New or changed behaviour:** the brief, then sign-off.
  - **No behaviour change** (a refactor, a speed-up that promises nothing new): nothing to sign off; it must end with everything still verified. A speed-up that is a promise ("1,000 items load in under a second") is a use case like any other.
- **Bug fixes take the same steps.** Step 4 decides what is wrong: the use case (change it, with sign-off) or the code (the use case is right: add the missing scenario, a red test that reproduces the bug, then the fix).
- **The brief names what it replaces**, so an earlier decision is never silently overwritten.
- **Can it fail?** Between red and green, a planted defect must turn the tests red. A test that cannot fail does not test the use case.
- **When the agent's code touches marked code, or adds a behaviour no use case covers,** it says so and goes back to step 4. It never leaves a use case quietly stale.
- **See it (step 7)** is separate from CI proof: anything the user will see is performed the way they will use it. The owner trying a build and asking for a change is the normal path back to step 4, not a failure.

## 5. Fitting new use cases in (step 4)

Step 4 works in two steps, so the person's idea is never watered down by what already exists before they have seen it:

```text
 STEP 1: the idea, in the person's words        STEP 2: how it meets what already exists
 ───────────────────────────────────────        ────────────────────────────────────────
 the golden path(s), as they see them    ──▶    search --like with each golden path
 (nothing reshaped yet: the idea stays          ─▶ the use cases it touches
  intact before it is compared)                 ─▶ for each one, how it fits (below)
                                                            │
                                                            ▼
                                                  the brief, then sign-off (step 5)
```

Every brief describes how it fits with the same six words, in every repo:

| Fit | Meaning | Example |
|---|---|---|
| **new** | nothing like it exists | "Export a report as PDF" |
| **extends** | an existing use case gains a scenario or an edge | login gains "locked after 5 tries" |
| **changes** | an existing use case behaves differently from now on | "refunds within 30 days" becomes "within 14" |
| **replaces** | an old use case goes, and this takes its place | "share by email" becomes "share by link" |
| **conflicts** | they cannot both be true; the person decides which wins | new: "double tap zooms"; existing: "double tap likes" |
| **untouched** | related, but stays exactly as it is | listed, so the person sees what was checked |

- **Conflicts are never resolved by the agent:** they always come to the person as a choice, and become one of the other fits.
- **Untouched is shown too**, so the person sees what was checked and left alone, not only what changed.
- **The fits become one batch** (chapter 16 §14, ADR 031): new is a save that adds; extends and changes are saves that update; replaces is a save and a remove. `render proposal` is what step 5 signs off; `apply --dry-run` shows the same batch in the order it will run (delete, add, update), and `apply` writes exactly that, all or nothing.

## 6. Sign-off by tier (steps 5 and 7)

There are two moments, and the use case's value tier decides who signs at each:

```text
                 5 BEFORE THE CODE                     7 AFTER SEEING IT
                 "is this the right behaviour?"        "does it really do that?"
                 (the proposal, in plain words)        (the build, tried for real)
 ──────────────  ─────────────────────────────────     ─────────────────────────────
 critical        the person, always                    the person, always
 core            the person, by default                the person, by default
 supporting      the agent, if the person said it may  the agent, if the person said it may
                 (it asks once, not per change)        (it says what it checked)
```

- **Critical is fixed:** it always comes to the person at both moments, and no setting hands it to an agent.
- **"If the person said it may"** is one permission given up front ("you can handle supporting changes in this repo"), asked once, not before every change. Without it, everything comes to the person.
- **The fast path goes through this too:** a papercut on a critical use case is still the person's to confirm, in its one line.

**Recorded on the use case.** A sign-off before the code is a decision about the promise, so it lives with the use case, committed and reviewed (chapter 02, `approved`): who, the day, and a fingerprint of the promise (its id, title, description, value tier, intent, scenarios and out of scope), computed as chapter 11 §89.9 says. It is written by `use-cases approve`, or by `apply --approved-by` for a signed-off batch, never by hand or by `save`.

```text
the person approves the proposal ──▶ apply --approved-by Sam ──▶ each use case in it is approved
later, its promise changes        ──▶ the fingerprint no longer matches ──▶ "changed since approved"
```

- Changing how a use case is proven (its routes, tests or links) keeps the approval; changing what it promises does not.
- What changed since the approval is in the version history: the approval and the wording it approved were committed together.
- The record says who approved; that a person, not an agent, gave the name is checked where the commit is reviewed.
- The sign-off after seeing it (step 7) is a verdict on a route someone performs, recorded like any verdict; what it must show is chapter 23's.

**The gate.** With `sign_off: required` in the root `use-cases.yml`, the gate holds a READY use case whose promise is not approved as it reads now: critical blocks, core and supporting warn, `--strict` blocks all three, and drafts never block (chapter 16 §10). It is per repo, because adopting it in a repo with no approvals would block every critical use case on the first day: step 0's setup asks whether to turn it on, and `use-cases approve --all --by NAME`, after a review, catches up in one commit.

## 7. One layout: templates

Everything the person reads about use cases uses one layout, in every repo and every host.

```text
        structured data (what show and save --dry-run already return as JSON)
                                   │
          ┌────────────────────────┼─────────────────────────┐
          ▼                        ▼                         ▼
   PLAIN (the core, always)  PREMIUM (optional)        PREMIUM (optional)
   a fixed text layout,      a rich, visual view in    another host's own view
   in any terminal or agent  one host                  (a side panel, an IDE)
```

- **The plain layout is the contract**, in the core: one fixed text layout for a use case, and for a proposal (a set of changes: new, changed, removed, and what each touches). Every host can show it.
- **Premium views are renderers of the same data**, in the agent layer: optional, host-specific, and never adding content. For example, a Claude artifact. The plugin stays universal.
- **Plain words first, ids last; one screen; bold headers.** Headers are bold in a terminal (as status colours are, and never with `NO_COLOR`) and plain capitals elsewhere: in a chat the layout sits in a code block, so its boxes keep their shape. A premium view draws the same model with its own headings. The words and the layout are the same everywhere.
- **The symbols are the six fits** (section 5): `+` new, `~` changes or extends, `−` replaces, `=` untouched; a conflict is **YOUR CALL**, a choice for the person.
- **In the flow:** step 5 signs off exactly the proposal it shows, and step 8 reports in the same layout.

The four formats, shown for one request, "lock accounts after too many wrong passwords":

**2 Intent:** what and why, in a few lines; asked for only when the request lacks them.

```text
WHAT   Lock an account after repeated wrong passwords
WHY    Stop people guessing customers' passwords
WHO    customers signing in · support staff who unlock accounts
```

**4 Brief:** one card for each use case the change adds, changes or removes, its id at the top right. Untouched use cases are listed in the proposal, without a card; a removed one's card shows only what goes.

```text
┌──────────────────────────────────────── shop.login.signin ──┐
│                                                             │
│  CHANGES · critical                                         │
│  Sign in                                                    │
│                                                             │
│  NOW                                                        │
│    After 5 wrong passwords, the account locks.              │
│                                                             │
│  WAS                                                        │
│    No limit.                                                │
│                                                             │
│  SCENARIOS                                                  │
│    ✓ golden   right password → signed in                    │
│    ◇ edge     5th try is right → signed in, no lock         │
│                                                             │
│  NOT INCLUDED                                               │
│    ✗ locking by IP address                                  │
│                                                             │
│  PROVEN BY                                                  │
│    unit tests · you trying it on staging                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**5 Sign-off:** the proposal, the whole change on one screen, ids last.

```text
PROPOSAL · Lock accounts after too many wrong passwords

  + NEW        Unlock by email link     you'll see: "Locked? Check your email"
  ~ CHANGES    Sign in                  you'll see: a lock message after 5 tries
  − REPLACES   Unlock by phoning support
  = UNTOUCHED  Remember me              (checked, stays as it is)

  YOUR CALL    how long a lock lasts:  1) 15 minutes   2) until unlocked by email
  SIGN-OFF     yours: 2 critical, 1 core
  ids          shop.login.unlock-email · shop.login.signin · shop.login.unlock-phone · shop.login.remember
```

**8 Results:** what was done, and how each change was proven, ids last.

```text
RESULTS · Lock accounts after too many wrong passwords

  ✓ Sign in                     unit-tests ✓ · staging ✓
  ✓ Unlock by email link        unit-tests ✓ · staging ✓
  − shop.login.unlock-phone     removed
  gate   passes
  ids    shop.login.signin · shop.login.unlock-email · shop.login.unlock-phone
```

### Drawn by the core: `use-cases render`

The agent never draws a layout. It supplies what only the conversation knows, and the core draws the rest from the workspace, so every repo and every agent shows the same thing (ADR 033).

```text
intent.yml    ──▶ use-cases render intent    --file F|-
proposal.yml  ──▶ use-cases render brief     --file F|-     the cards
              ──▶ use-cases render proposal  --file F|-     what is signed off
              ──▶ use-cases apply            --file F|-     the same file, applied as it is
              ──▶ use-cases render results   --file F|-     after it is applied and verified
```

| Layout | The agent supplies | The core fills in |
|---|---|---|
| intent | `what`, `why`, `who` (a list) | nothing: it comes before any use case |
| brief | the proposal file | each card: the fit, tier, title, NOW (the new intent), WAS (the current one, when it changes), scenarios, out of scope, and how it is proven, from its routes |
| proposal | the proposal file | each change's fit, title and tier, in the order new, changes, replaces, untouched; who signs, by tier |
| results | the proposal file | each saved use case's status and the checks behind it; the removed ones; whether the gate passes |

**The proposal file** is the batch `apply` takes (`remove`, `save`), plus `title`, `untouched` (ids checked and left alone), `fits` (`extends` or `changes`, for a save that changes an existing use case; the other fits follow from the batch), `you_see` (per use case, what the person will see), `decisions` (each a `question` and two or more `options`) and `golden` (per use case, the scenarios that are its golden path; the first by default). `apply` ignores those, so the file the person signed off is the file applied.

The SIGN-OFF line counts what changes or goes, by tier; a use case with no value tier counts as the person's ("N without a tier"), because without a tier's permission everything comes to the person. In `--json` the counts are `critical`, `core`, `supporting` and `no_tier`, each present only when it is more than none. `render brief` and `render proposal` refuse a proposal file `apply` would refuse, with the same message; `render results` draws only a proposal that is applied: every removal gone and every save's promise (section 6) as the workspace holds it.

`render` needs a workspace for every layout but intent. With `--json` it returns the layout's `model`, for any view to draw, and the plain `text` the core draws from it; the agent shows the person that text as it is. `use_cases_render` is the same for agents.

## 8. Specified elsewhere

Input: a survey of four sessions using today's plugin, `docs/research/plugin-survey.md`.

| Part | Covers |
|---|---|
| Each step's check (chapter 22) | the command output that shows each step of the flow is done, for an agent following it |
| Seeing it (chapter 23) | step 7: showcases, and what "done" means for what people see |
