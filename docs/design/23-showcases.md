# 23 — Showcases

**Phase:** 4 — Agent Layer  
**Status:** Specification (locked)

## 1. Purpose

Green tests do not mean a use case works: what the use case says and what the code does can still differ, most of all for what people see and feel. A showcase closes that gap at step 7 of the flow (chapter 21): someone performs the use case the way its user will, and someone signs off what they saw.

A showcase is temporary. It is planned for one occasion, performed, shown, and thrown away. Nothing about it is kept in the use cases or the core. What it proved can be kept, as an ordinary verdict with its evidence (section 5).

## 2. The axes

Each showcase is planned on two axes, by the agent with the person:

```text
                         WHO SIGNS IT OFF
          the agent          another agent           the person
          (performed it)     (independent review)    (it is for them)
        ┌──────────────────┬──────────────────────┬──────────────────────┐
 LIVE   │ the agent drives │ a reviewer watches   │ the agent drives it  │
 (now)  │ it and judges it │ it happen            │ in front of them;    │
        │                  │                      │ they say yes, or     │
        │                  │                      │ change X             │
        ├──────────────────┼──────────────────────┼──────────────────────┤
 RECORD-│ the agent        │ the agent performs,  │ the agent performs,  │
 ED     │ performs, keeps  │ a reviewer judges    │ then shows them the  │
 (later)│ the evidence     │ the evidence         │ evidence to sign off │
        └──────────────────┴──────────────────────┴──────────────────────┘
          WHEN IT IS SEEN
```

and two more choices:

| Choice | Range | For example |
|---|---|---|
| **How real** | a mock or preview ··· a test build ··· the real thing | a UI preview with fake data, the staging app, production |
| **What the evidence is** | whatever suits the use case | a video for an animation · screenshots or frames · a text output or a file · an artifact · a measurement ("closes in 0.3 s") |

- **Not every use case is worth a video.** An export is better shown as the file it writes; a speed-up as its measurement.
- **The person's column follows the tiers** (chapter 21 §6): a critical use case always ends with the person signing off; an agent signs off only where the person said it may.

## 3. What to show

```text
smoke    the critical use cases, as status --json gives each use case's value tier
feature  the use cases a proposal changed (chapter 21 §7)
full     everything, or a group (chapter 03)
```

The person can always ask for more: their new feature alongside whatever else they want to see.

## 4. A showcase run

```text
 plan (the agent, with the person)   perform            show              throw away
 ─────────────────────────────────   ───────            ────              ──────────
 which use cases, and where on   ──▶ the agent runs ──▶ live, or the  ──▶ the plan, and any
 the axes; the evidence that         each use case's    evidence           evidence not kept
 suits each                          "try it" steps     afterwards
                                     on the build
```

- **The steps are the use case's own.** A "try it" check's procedure (an acceptance route, chapter 06) is the script the showcase performs. A use case with nothing to perform has nothing to showcase.
- **Agent first, then the person,** as needed: the agent performs it for itself or another agent, and for the person when they are to sign off.
- **"Change X" is the normal outcome** of a showcase for the person: it goes back to the brief (chapter 21, step 4).

## 5. Keeping what it proved

When a showcase passes or fails, its result can be kept with the commands that already exist:

```text
use-cases record shop.cart.drop try-it pass "tried by Sam, live, on the test build" --attach drop.mov notes.txt
```

- **An ordinary verdict** on the use case's "try it" check: who signed it off, and how it was seen, in its message, in plain words.
- **The evidence is kept with it,** sealed in that run's folder by its content (chapter 12): the recording, screenshots, output files.
- **It goes stale** when what it performed changes, as every verdict does, so an old showcase never vouches for new code.
- **Kept like test results:** in the checkout's results store, never committed.
- **What "done" means for what people see:** a scenario someone will see has a gating "try it" check, so the use case cannot read verified until a showcase has passed it.

## 6. What it proves

`test_showcase.py`: a showcase kept as a verdict with its evidence attached and sealed; the use case verified only once it is; stale once what it performed changes; a failed showcase blocking the gate. The core is unchanged: the commands of chapters 13 and 16 carry it.

## 7. Final model

```text
plan on the axes ──▶ perform the "try it" steps ──▶ show (live or recorded) ──▶ throw the showcase away
                                                          │
                                       keep what it proved, if wanted: record … --attach
                                       an ordinary verdict, stale when the code changes
```
