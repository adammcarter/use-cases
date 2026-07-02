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

- `use-case-matrix` when the task is to maintain behavior inventory or evidence records.
- `walkthrough` when the user wants broad explanation, caveats, edge cases, or provenance rather than a live run.
- Ordinary implementation/testing when no proof or presentation is requested.

## Plan Mode vs Run Mode

- Plan mode prepares only. Use `ucm plan showcase --json` or `ucm capsule plan --json`.
- Run mode records actual performed events. Use `ucm showcase start --json` only when the request clearly asks for a live run or the user agrees to perform one.
- A generated plan must not be described as a completed demo.

## Live Run Rules

- Record observations before verdicts with `ucm showcase record-observation --json`.
- Record verdicts with `ucm showcase record-verdict --json`.
- When a verdict fails or blocks, record a decision with `ucm showcase decide --json` before finishing.
- Pause or resume with `ucm showcase pause --json` and `ucm showcase resume --json`.
- Correct mistaken entries with `ucm showcase correct --json`; do not edit JSONL history by hand.
- Finish with `ucm showcase finish --json` and inspect state with `ucm showcase status --json`.

## Presentation Formats

Every plan item carries a chosen `presentation_format`. Present each item in exactly one of the six fixed formats, reading the choice from the plan item (never inventing one):

- Testing (emoji tube) - runs it live: Run / Expect / Got.
- Comparing (emoji scales) - guardrail or before-after: a blocked row and an allowed row.
- Inspecting (emoji magnifier) - examine the real artifact: In / Look.
- Reviewing (emoji scroll) - cite an earlier run: From / Shows (not re-run now).
- Over to you (emoji raised hand) - needs the human: numbered steps then Confirm: yes / no.
- Explaining (emoji speech balloon) - description only: plain text then "not run - explanation only".

Render the fixed emoji + verb header for the chosen format so the user can scan the mode at a glance. The header verb is a promise and must not lie:

- A failed Testing item shows Got with a cross mark. It must never be re-narrated as Explaining; a live failure stays a live failure.
- Over to you stays open on Confirm: yes / no until a real human answers. The agent can never fill that answer in.
- A check mark, a Reviewing "Shows", or a "Confirm: yes" must correspond to a real recorded result, never to agent prose alone.

## Approval Boundary

Agents may record agent observations and agent verdicts when allowed. Agents must not claim user approval, user sign-off, or user verification. User approval requires the designated trusted confirmation path, such as `ucm showcase approve --json` with an explicit user actor in a context where the user actually confirms.

Do not say Claude, Codex, Copilot, or OpenCode support is verified unless host evidence exists. A canonical skill, host profile, or passing doctor check is not live host workflow evidence.
