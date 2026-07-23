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

## Demo Gates

Every live run passes three user gates. Ask each gate with the host's structured question tool (`AskUserQuestion` on Claude; the closest native single-tap prompt elsewhere) so the user answers with a tap, not typed commands. The agent operates every command in this flow; the user only answers questions.

- Gate 1 - Ready. Before `uc showcase start`, ask whether the user is ready to see the demo. Never start a live run from inference, a generated plan, or momentum alone; "not yet" means hold with nothing recorded.
- Gate 2 - Driver. In the same prompt, ask who drives the demo: the agent (offer only when the agent can genuinely execute the steps - scripts, AppleScript, computer use) or the user following the plan's steps. Agent-driven items present as Testing or Inspecting; user-driven items present as Over to you, where Confirm stays human.
- Gate 3 - Verdict. After the demo, ask exactly three options: approve, reject, or talk about this. Approve and reject both accept optional free-text notes from the user.

Wire the Gate 3 answer to the run record. The gates change how the answer is collected (a tap, not typed text), never what an answer is worth - an answer given through the question tool carries exactly the trust a typed one always did:

- Approve: treat it as the user's acceptance of the demo, quoting their answer and notes verbatim; record any remaining decisions with `uc showcase decide --json` and close with `uc showcase finish --json`. Act only on a fresh, explicit approve answer for that exact run - never a stale, inferred, or agent-authored one.
- Reject: record the user's decision and notes with `uc showcase reject --statement`, record any failing verdicts' decisions with `uc showcase decide --json`, then `uc showcase finish --json`.
- Talk about this: `uc showcase pause --json`, discuss, then re-ask Gate 3. Discussion alone records nothing.

The signed sign-off tier (`uc approve-run` + `uc showcase approve --approval-token`) is unchanged by these gates: it remains the separate, opt-in release/audit path, and stays out of the everyday demo flow unless the run's approval policy demands it.

## Live Run Rules

- Record observations before verdicts with `uc showcase record-observation --json`.
- Record verdicts with `uc showcase record-verdict --json`.
- When a verdict fails or blocks, record a decision with `uc showcase decide --json` before finishing.
- Pause or resume with `uc showcase pause --json` and `uc showcase resume --json`.
- Correct mistaken entries with `uc showcase correct --json`; do not edit JSONL history by hand.
- Finish with `uc showcase finish --json` and inspect state with `uc showcase status --json`.

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

Agents may record agent observations and agent verdicts when allowed. Agents must not claim user approval, user sign-off, or user verification. User approval requires the designated trusted confirmation path, such as `uc showcase approve --json` with an explicit user actor in a context where the user actually confirms.

Do not say Claude, Codex, Copilot, or OpenCode support is verified unless host evidence exists. A canonical skill, host profile, or passing doctor check is not live host workflow evidence.
