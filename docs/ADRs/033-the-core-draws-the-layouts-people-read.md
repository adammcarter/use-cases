# ADR 033: The core draws the four layouts people read, from one proposal file

## Status

Accepted - 2026-10-12

## Context

People decide behaviour by reading use cases (chapter 21), and the survey of sessions using today's plugin (`docs/research/plugin-survey.md`) found owners never read YAML: they approved plain-English summaries each agent drew its own way. The owner agreed four canonical layouts (intent, the brief's cards, the proposal, the results) and chose to have the core draw them, so they are the same in every repo and from every agent.

## Decision

- **`use-cases render intent|brief|proposal|results --file F|-`**, and the tool **`use_cases_render`**.
- **The agent supplies only what the conversation knows;** the core fills in the rest from the workspace: tiers, NOW and WAS, scenarios, out of scope, how each is proven, who signs by tier, statuses and the gate.
- **One proposal file** drives the brief, the proposal, `apply` and the results: the batch (`remove`, `save`) plus `title`, `untouched`, `fits`, `you_see`, `decisions` and `golden`, which `apply` ignores. What the person signed off is exactly what is applied.
- **A model, then text:** `--json` returns the layout's model for any view to draw, and the plain text the core draws from it. The plain text is the contract; premium views draw the same model and add nothing.
- Headers are bold in a terminal and plain capitals elsewhere; the words and the layout never change.

## Consequences

- Good: every agent and repo shows the same layouts, by construction rather than by instruction.
- Good: the proposal and the change applied cannot drift apart: they are one file.
- Cost: one more command and tool, and the layouts are part of the contract, so changing one is a design change.

## Considered Options

- **Formats documented in the guides, drawn by agents:** no core command, but layouts drift between agents and repos, which is what the survey found.
- **The layouts inside existing commands** (`apply --dry-run` drawing the proposal): fewer commands, but intent and results have no command of their own, and the proposal needs what only the conversation knows.

## Confirmation

- `test_render.py`: intent with no workspace; a card per change, id top right, every row the card's width; NOW, WAS, scenarios with a golden path by default or as named; a removed card showing only what goes; no escape codes outside a terminal; the proposal's order, symbols, you'll see, your call, sign-off by tier, ids last; extends; every kind of bad proposal refused; the same file applied, its results drawn only after.
- `test_mcp.py`: a layout through the tool, and the same batch applied.

## Related Links

- `docs/design/21-agent-workflows.md` §7
- `docs/schemas/output/cli-render.schema.json`
- ADR 031 (batches), ADR 032 (sign-off), ADR 027 (agents get the commands as tools)
