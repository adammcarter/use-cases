---
name: showcase
description: Use when preparing or performing a live user-visible showcase, demo, sign-off flow, pre-merge acceptance run, or high-value feature proof from use cases and evidence.
---

# Showcase

Use this skill for live, high-value demonstration work where the agent may run the show or guide the user through it.

Generated plans, walkthroughs, capsules, and runbooks are prepared material only. They are not proof, not performed, and not approval until a showcase run records actual events.

## Prefer This Skill

- The user asks for a live demo, showcase, final acceptance proof, or pre-merge demonstration.
- A small set of critical or golden-path use cases should be selected for user-visible proof.
- A performed run needs observations, verdicts, failure decisions, pause/resume, correction, finish, or approval handling.

## Defer To

- `use-cases` when the task is to maintain behavior inventory or evidence records.
- `walkthrough` when the user wants broad explanation, caveats, edge cases, or provenance rather than a live run.
- Ordinary implementation/testing when no proof or presentation is requested.

## Plan Mode vs Run Mode

- Plan mode prepares only. Use `uc plan showcase --json` or `uc capsule plan --json`.
- Run mode records actual performed events. Use `uc showcase start --json` only when the request clearly asks for a live run or the user agrees to perform one.
- A generated plan must not be described as a completed demo.

## The Demo Card Loop

Every live plan item runs as a fixed loop built around a **demo card**. The card is the demo; every question is only its confirm button. The user should be able to follow the whole run by reading cards alone - which is why the card is always posted first, on its own, before any question can appear.

### The card

Rendered inline in chat as markdown (not a code block), in exactly this shape:

    ### 🧪 Demo N of T — <plain-English promise of the behavior>

    `<use_case_id.scenario>` · live

    **Steps**
    1. <numbered, exact actions the agent will perform>
    2. <...>
    3. <always end by returning the user's focus/context to where they were>

    **Expect**
    <one crisp statement of what the user should see, phase by phase if the demo has phases>

On the post-run reprint the same card is repeated in full with one section appended:

    **Actual**
    <what actually happened / what the evidence recorded> — the user's eyes decide.

The card grows; it never mutates. Follow-up turns reprint the whole card with the new information added, so any single message stands alone.

### The loop, per item

- Turn 1 - Present. Send the card (Steps + Expect) as its OWN message and END the turn - no question tool call, no other tool calls after the card. The card must be on the user's screen before anything else happens.
- Turn 2 - Gate. In the NEXT turn, ask Gate 1 with the host's structured question tool (`AskUserQuestion` on Claude; the closest native single-tap prompt elsewhere): ready to run this card, options "Ready - go" / "Not yet". A one-line pointer ("Card above - ready?") may precede the question; the full card lives in the previous message. Never start from inference, a generated plan, or momentum; "Not yet" holds with nothing recorded.
- Turn 3 - Perform and grade. Only after "Ready - go": perform exactly the card's Steps - nothing more, nothing less - then send the full card reprinted with **Actual** filled as its OWN message and end the turn, then ask Gate 3 (verdict) in the following turn with options **in this order: Approve, Reject, Run it again**. Approve and Reject accept optional free-text notes; "Run it again" re-performs the same card's Steps and re-asks the verdict, recording nothing in between. Discussion arrives through the host's free-text option and maps to `uc showcase pause --json`, talk, then re-ask.
- Gate 2 - Driver - is asked once per run (or per item when it genuinely varies): who drives, the agent (offer only when the agent can genuinely execute the steps - scripts, AppleScript, computer use) or the user following the card's Steps. Agent-driven items present as Testing or Inspecting; user-driven items present as Over to you, where Confirm stays human.

### The card-first visibility rule (hard)

The card is posted as its OWN message, the turn ends, and only then is its question asked. A question NEVER rides in the same message as its card, and a question with no card delivered in a previous message is invalid.

This rule exists because both observed failure modes are real and repeat:

- Hosts that render structured questions as a modal (e.g. Claude Code's fullscreen TUI) flush assistant text to the transcript only when the turn completes. A question in the same message as the card throws the modal up first, hides the card behind it, and - if the user rejects or interrupts - the card never renders at all. From the user's side the card never existed. Ending the turn after the card is the only way to ENSURE it is shown before the question appears.
- After an interruption, rejection, or tool error, the natural retry is to re-issue the last *tool call* (the bare question). That is wrong. **A retry re-composes from the card: repost the full card as its own message, end the turn, then re-ask.** Never assume an earlier card is "still on screen".

### Wiring verdicts to the record

The gates change how the answer is collected (a tap, not typed text), never what an answer is worth - an answer given through the question tool carries exactly the trust a typed one always did:

- Approve: treat it as the user's acceptance of that card, quoting their answer and notes verbatim; record the observation and verdict, then move to the next item - whose Turn 1 must begin with its own card message, never a bare ready-gate. Record remaining decisions with `uc showcase decide --json` and close the run with `uc showcase finish --json`. Act only on a fresh, explicit approve answer for that exact run - never a stale, inferred, or agent-authored one.
- Reject: record the user's decision and notes with `uc showcase reject --statement`, record any failing verdicts' decisions with `uc showcase decide --json`, then `uc showcase finish --json`. A rejected live card stays a live failure; it is never restaged into a pass or re-narrated as an explanation.
- Run it again: re-perform, reprint the card with the fresh Actual, re-ask. Repeat runs overwrite nothing; only the verdict the user finally gives is recorded.

The signed sign-off tier (`uc approve-run` + `uc showcase approve --approval-token`) is unchanged by these gates: it remains the separate, opt-in release/audit path, and stays out of the everyday demo flow unless the run's approval policy demands it.

## Live Run Rules

- Record observations before verdicts with `uc showcase record-observation --json`.
- Record verdicts with `uc showcase record-verdict --json`.
- When a verdict fails or blocks, record a decision with `uc showcase decide --json` before finishing.
- Pause or resume with `uc showcase pause --json` and `uc showcase resume --json`.
- Correct mistaken entries with `uc showcase correct --json`; do not edit JSONL history by hand.
- Finish with `uc showcase finish --json` and inspect state with `uc showcase status --json`.

## Presentation Formats

Every plan item carries a chosen `presentation_format`. Present each item in exactly one of the six fixed formats, reading the choice from the plan item (never inventing one). Testing items use the demo-card shape above (Steps / Expect / Actual); the other formats keep their fixed field pairs:

- Testing (emoji tube) - runs it live: Steps / Expect / Actual, as the demo card.
- Comparing (emoji scales) - guardrail or before-after: a blocked row and an allowed row.
- Inspecting (emoji magnifier) - examine the real artifact: In / Look.
- Reviewing (emoji scroll) - cite an earlier run: From / Shows (not re-run now).
- Over to you (emoji raised hand) - needs the human: numbered steps then Confirm: yes / no.
- Explaining (emoji speech balloon) - description only: plain text then "not run - explanation only".

Render every format as an inline markdown card in the demo-card style: a `###` heading with the fixed emoji plus a plain-English title, the item id beneath it, then the format's fields as bold titles on their own lines. Non-live formats follow the same two rules as Testing cards: the card is posted as its own message before any question is asked (card-first visibility), and follow-up turns reprint the whole card with new information appended.

The header verb is a promise and must not lie:

- A failed Testing item shows Actual with a cross mark. It must never be re-narrated as Explaining; a live failure stays a live failure.
- Over to you stays open on Confirm: yes / no until a real human answers. The agent can never fill that answer in.
- A check mark, a Reviewing "Shows", or a "Confirm: yes" must correspond to a real recorded result, never to agent prose alone.

## Approval Boundary

Agents may record agent observations and agent verdicts when allowed. Agents must not claim user approval, user sign-off, or user verification. User approval requires the designated trusted confirmation path, such as `uc showcase approve --json` with an explicit user actor in a context where the user actually confirms.

Do not say Claude, Codex, Copilot, or OpenCode support is verified unless host evidence exists. A canonical skill, host profile, or passing doctor check is not live host workflow evidence.
