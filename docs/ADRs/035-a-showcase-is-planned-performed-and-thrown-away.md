# ADR 035: A showcase is planned, performed and thrown away; what it proved is an ordinary verdict

## Status

Accepted - 2026-10-12

## Context

Green tests do not mean a use case works, most of all for what people see and feel: the survey of sessions using today's plugin (`docs/research/plugin-survey.md`) found nearly every owner correction came from trying the build. The owner's notes describe showcases from smoke tests to the whole stack, performed by agents for people or for other agents. The owner set the shape: showcases differ along axes (who signs off, live or recorded, how real, what evidence), they are superficial, planned for one occasion and thrown away, and the existing ability to record verdicts with evidence is how what they proved is kept.

## Decision

- **A showcase is planned on axes** by the agent with the person: who signs it off (the agent, another agent, the person), when it is seen (live or recorded), how real (a mock, a test build, the real thing), and what evidence suits each use case (a video, screenshots, an output, an artifact, a measurement).
- **It performs the use case's own "try it" steps** (an acceptance route's procedure), and is thrown away afterwards: nothing about it is kept in the use cases or the core.
- **What it proved can be kept** as an ordinary verdict on the "try it" check: `record` with who and how in its message and `--attach` for the evidence. It goes stale as every verdict does.
- **What "done" means for what people see:** a scenario someone will see has a gating "try it" check, so the use case cannot read verified until a showcase has passed it.
- The person's column follows the tiers (ADR 032): critical always ends with the person.
- **No core change.**

## Consequences

- Good: showcases fit each occasion, and leave no files to maintain.
- Good: what was seen counts exactly as other verdicts do, and an old showcase never vouches for new code.
- Cost: who signed off and how it was seen are plain words in the verdict's message, not fields the core checks; the evidence attached is what backs them.

## Considered Options

- **Showcase settings on each use case and new verdict fields** (evidence kinds, how real, who): enforceable, but showcase detail would live in the use cases and the store when the owner wants it superficial.
- **Nothing kept at all:** simplest, but a showcase that proved something would leave no trace the gate can see.

## Confirmation

- `test_showcase.py`: a verdict with its evidence attached and sealed; verified only once it is; stale once what it performed changes; a failed showcase blocking the gate.
- `test_docs.py`: the showcase skill names only real commands and flags.

## Related Links

- `docs/design/23-showcases.md`
- `docs/design/21-agent-workflows.md` (step 7), `docs/design/22-ucdd-skill.md`
- ADR 032 (sign-off by tier)
