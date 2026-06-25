---
name: presentation-showcase
description: Use when preparing or performing a live user-visible showcase, demo, sign-off flow, pre-merge acceptance run, or high-value feature proof from use cases and evidence.
---

# Presentation Showcase

Use this skill for live, high-value demonstration work where the agent may run the show or guide the user through it.

Generated plans, walkthroughs, capsules, and runbooks are prepared material only. They are not proof, not performed, and not approval until a showcase run records actual events.

## Prefer This Skill

- The user asks for a live demo, showcase, final acceptance proof, or pre-merge demonstration.
- A small set of critical or golden-path use cases should be selected for user-visible proof.
- A performed run needs observations, verdicts, failure decisions, pause/resume, correction, finish, or approval handling.

## Defer To

- `use-case-matrix` when the task is to maintain behavior inventory or evidence records.
- `presentation-walkthrough` when the user wants broad explanation, caveats, edge cases, or provenance rather than a live run.
- Ordinary implementation/testing when no proof or presentation is requested.

## Plan Mode vs Run Mode

- Plan mode prepares only. Use `presentation-skills plan showcase --json` or `presentation-skills capsule plan --json`.
- Run mode records actual performed events. Use `presentation-skills showcase start --json` only when the request clearly asks for a live run or the user agrees to perform one.
- A generated plan must not be described as a completed demo.

## Live Run Rules

- Record observations before verdicts with `presentation-skills showcase record-observation --json`.
- Record verdicts with `presentation-skills showcase record-verdict --json`.
- When a verdict fails or blocks, record a decision with `presentation-skills showcase decide --json` before finishing.
- Pause or resume with `presentation-skills showcase pause --json` and `presentation-skills showcase resume --json`.
- Correct mistaken entries with `presentation-skills showcase correct --json`; do not edit JSONL history by hand.
- Finish with `presentation-skills showcase finish --json` and inspect state with `presentation-skills showcase status --json`.

## Approval Boundary

Agents may record agent observations and agent verdicts when allowed. Agents must not claim user approval, user sign-off, or user verification. User approval requires the designated trusted confirmation path, such as `presentation-skills showcase approve --json` with an explicit user actor in a context where the user actually confirms.

Do not say Claude, Codex, Copilot, or OpenCode support is verified unless host evidence exists. A canonical skill, host profile, or passing doctor check is not live host workflow evidence.
