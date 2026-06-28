# Presentation Formats Spec

Status: draft for sign-off
Date: 2026-06-28

## Problem

The product has no GUI. The agent's chat/terminal is the only display surface,
so the agent itself presents each feature by running commands, showing output,
and narrating.

Today the *way* a feature is shown is **inferred, never chosen**:

- `delivery_kind` (`live_demo` / `evidence_review` / `explanation`) is derived
  from a row's verification requirements.
- `control_mode` is derived from whether command steps exist.

Two gaps follow:

1. The agent/user cannot decide up front **how best to present each feature**.
2. There is **no fixed format** the agent uses to tell the user *what it is
   testing* — capsule runbook steps are freeform, so presentations are
   inconsistent and a failed live demo can quietly read like an explanation.

## Decision

Introduce **six presentation formats**. The agent picks one per item up front,
and surfaces it to the user with a fixed, scannable header + body.

Design principles (settled with two design rounds and an independent review):

- **Presentation is chosen, not derived.** How we show a feature is a
  deliberate choice; verification policy only *constrains what we may claim*,
  it does not pick the format.
- **Keep it light.** The format is the honesty surface, not a compliance
  artifact. No always-on metadata, no double classification, no filler.
- **The verb cannot lie.** The header verb tells the user the mode honestly; a
  live test that fails cannot silently become an explanation.

## The six formats

Each format is an honest verb + emoji header, a `{feature}`, and a few slots.

**🧪 Testing:** {feature}  ·  *runs it live*

```
Run:     {command}
Expect:  {what success looks like}
Got:     {actual}                     ✓ / ✗
```

**⚖️ Comparing:** {feature}  ·  *guardrail / before–after*

```
✗  {bad command}    → should be blocked    → {got}
✓  {good command}   → should work          → {got}
```

**🔎 Inspecting:** {feature}  ·  *examine the real artifact*

```
In:    {file:lines}
Look:  {the part that matters}
```

**📜 Reviewing:** {feature}  ·  *cite an earlier run*

```
From:   {earlier run / date}
Shows:  {what it proved}              (not re-run now)
```

**🙋 Over to you:** {feature}  ·  *needs the human (one or many steps)*

```
1.  {step}        → expect: {what you see}
2.  {step}        → expect: {what you see}

Confirm:  yes / no
```

**💬 Explaining:** {feature}  ·  *description only*

```
{plain explanation}

(not run — explanation only)
```

## The honesty rule

The emoji + verb is a promise that cannot be broken at render time:

- A **🧪 Testing** that fails shows `Got: ✗`. It cannot be re-rendered as a
  **💬 Explaining** (no silent fallback from a live claim to a narrated one).
- **🙋 Over to you** stays open until the human answers `yes / no`. The agent
  can never fill that answer in — only a human-origin event satisfies it.
- A `✓` / `Shows:` / `Confirm: yes` must correspond to a real recorded result,
  never to agent prose alone.

## Mapping to the existing model

| Format         | emoji | maps to `delivery_kind` |
| -------------- | ----- | ----------------------- |
| Testing        | 🧪    | live_demo               |
| Comparing      | ⚖️    | live_demo (contrast)    |
| Inspecting     | 🔎    | evidence_review (artifact) |
| Reviewing      | 📜    | evidence_review (ledger)   |
| Over to you    | 🙋    | (control: user_led)     |
| Explaining     | 💬    | explanation             |

`delivery_kind` stays as a **computed compatibility projection** for existing
consumers; the chosen format becomes the source of truth for how an item is
presented. `showcase` mode should stop hard-forcing `live_demo` and instead
prefer-live-where-safe so destructive/external/human-judgment items get the
right format.

## Scope

In scope for v1:

- The six formats above as the agent-facing presentation surface.
- The chosen format recorded per plan/capsule item (replacing pure
  auto-derivation), with `delivery_kind` kept as a projection.
- The render-time honesty rule (verb cannot lie; `🙋` cannot self-answer).

Out of scope for v1 (deliberately deferred — flagged by the independent review
as the deeper layer, valuable but not needed to ship the formats):

- A typed **event schema** and per-claim **evidence-verifier contract** (a claim
  is only valid if the backing event's type, scope, run-context, and payload
  satisfy that claim's proof rule). This is the strongest follow-up: without it,
  a `✓` is only as trustworthy as the event it cites. Track separately.
- Versioned template registry, surface/target capability matrices, and any
  future GUI surface binding.

## Open questions

- Where the chosen format lives: per use-case row (as a hint/affordance) vs only
  on the presentation plan. Leaning: row carries affordances/constraints
  (`safe_live_demo`, `has_fixture`, `destructive_if_live`); the plan carries the
  actual choice.
- Whether `⚖️ Comparing` is its own format or a variant of `🧪 Testing`.
