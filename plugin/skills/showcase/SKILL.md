---
name: showcase
description: Use at step 7 of working use case first, to perform what the user will see the way they will use it, show it, and keep what it proved if wanted.
---

# Showcase

Step 7 of the flow: seeing it. Green tests do not prove that what people see and feel matches the use case. A showcase is planned with the person, performed, shown, and thrown away. What it proved can be kept as an ordinary verdict.

| Plan | Choices |
|---|---|
| What to show | smoke (the critical use cases), a proposal's use cases, a group, or everything |
| Who signs it off | the agent · another agent · the person (critical: always the person; core: the person, by default) |
| When it is seen | live · recorded |
| How real | a mock or preview · a test build · the real thing |
| What the evidence is | whatever suits it: a video, screenshots, an output file, an artifact, a measurement |

Perform each use case's "try it" steps. To keep what it proved: `use-cases record` with the verdict, who and how in the message, and `--attach` the evidence.

## 1. Plan it with the person

Ask about each row of the table, one at a time, with choices, proposing a default for each:

- **What to show.** For a change, the use cases its proposal saved. For smoke, the critical use cases: list them from `use_cases_status` (each READY use case carries its `value_tier`). For a group, `use_cases_status` with `group`. For everything, every use case `use_cases_status` lists. The person can always add more.
- **Who signs it off.** It follows the value tier: a critical use case always ends with the person; a core one ends with the person by default; a supporting one may be yours only where the person has said so.
- **Live or recorded.** Live: you perform it in front of them. Recorded: you perform it, then show them the evidence.
- **How real**, and **what the evidence is**: pick what suits each use case. An export is best shown as the file it writes, a speed-up as its measurement, an animation as a video. Not every use case is worth a video.

## 2. Perform it

The steps are the use case's own: each route with a `procedure` is a "try it" check, and its steps are the script. Read them with `use_cases_show`. A use case with nothing to perform has nothing to showcase; say so, and offer to add a "try it" route through the use-case-driven-development flow.

Perform each step on the build you agreed, exactly as written, and collect the evidence as you go. Perform it for yourself first; then for the person, when they are to sign off.

## 3. Show it

Live, or as the evidence afterwards. Say plainly what you did, what you saw, and where it differs from the use case. Ask: does it do what you expected, or change something?

"Change X" is the normal outcome, not a failure: it goes back to the brief (step 4 of the use-case-driven-development skill).

## 4. Keep what it proved, if wanted

Ask whether to keep the result. If so, record it on the use case's "try it" route, with who signed it off and how it was seen in the message, and the evidence attached:

```text
$ use-cases record basket.discounts try-it pass "tried by Sam, live, on the test build" --attach receipt.txt
recorded: basket.discounts / try-it → pass
→ use-cases status basket.discounts
```

Through the tool: `use_cases_record_verdict` with `use_case`, `route`, `status` (`pass` or `fail`), `message`, and `attach` (a list of files).

- The evidence is sealed with that verdict in the checkout's results store; it is never committed.
- The verdict goes out of date when what it performed changes, so an old showcase never vouches for new code.
- A failed showcase recorded as `fail` blocks the gate until it passes again.

## 5. Throw it away

Delete the plan and any evidence not kept. Nothing about a showcase stays in the use cases.

## Never

- Never record a pass for a step you did not perform, or for a person who did not see it.
- Never let an agent sign off a critical use case.
- Never record a verdict on a DRAFT: `use-cases record` refuses it.
