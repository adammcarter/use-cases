# ADR 034: The plugin ships the flow as skills, with a check for every step

## Status

Accepted - 2026-10-12

## Context

Chapter 21 defines how an agent works use case first. An agent follows it only if the plugin packages it, and only reliably if each step has a way to show it is done. The owner's notes ask for a use-case-driven-development skill, and mention file structure, migration, showcases and planning agents; the survey of sessions using today's plugin (`docs/research/plugin-survey.md`) found global start-up text in every session was noise.

## Decision

- **The plugin ships:** setup (step 0, asking first), the use-case-driven-development skill (the flow), adopting (one small area at a time, as the code is today), showcase (step 7, chapter 23), and the MCP server.
- **Every step of the flow ends on a check:** a command whose output shows it is done, which the agent reports. Red is a real failure, never an error; a test that passes before the change has a planted defect.
- **No file-structure skill** (the commands keep the structure), **no global start-up text** (AGENTS.md decides), **no planning agents yet.**
- Each skill holds its name, purpose and agreed table, and the steps an agent follows: what to ask the person and when, the commands and tools with their arguments, and what never to do.

## Consequences

- Good: an agent's progress is the commands' output, never its claim.
- Good: the whole flow is proven possible on a real repo, end to end.
- Cost: the skills are a second body of text beside the chapters; the check that every command and flag they name exists catches names, not wrong advice.

## Considered Options

- **One skill holding everything:** simpler to find, but setup and adopting run once, and would sit in every change's instructions.
- **A file-structure skill:** the layout is enforced by `save` and `apply`, so it would only repeat them.

## Confirmation

- `test_flow.py`: the whole flow on a real Python repo with real tests, every step's check met.
- `GuidesHeldTrueTests`: the plugin ships its four skills, every command, flag and file they name exists, and every agent tool and tool argument they name is one the MCP server offers (`GuideCheck`, `GuideToolCheck`); the setup skill writes the AGENTS.md block of chapter 22 exactly.

## Related Links

- `docs/design/22-ucdd-skill.md`
- `docs/design/21-agent-workflows.md`
- ADR 031 (batches), ADR 032 (sign-off), ADR 033 (the layouts)
