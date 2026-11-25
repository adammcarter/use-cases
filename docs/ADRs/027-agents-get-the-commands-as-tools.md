# ADR 027: Agents get the commands as MCP tools, and nothing more

## Status

Accepted - 2026-09-28

## Context

The agent layer lets AI agents use Use Cases. Agents work through tools, not typed commands. The question was which commands they get, and whether the agent layer may change how Use Cases behaves. The owner agreed the layer is "a second way in", built on the locked core without changing it, and that agents get every command except the ones that set up a repository, and `prune`, which deletes evidence.

## Decision

- `use-cases mcp` runs an MCP server over stdio, started by an agent's host.
- The tools: `use_cases_validate_files`, `use_cases_status`, `use_cases_verify_tests`, `use_cases_record_verdict`, `use_cases_links`, `use_cases_search` (ADR 029), `use_cases_show`, `use_cases_save` and `use_cases_remove` (ADR 028), `use_cases_apply` (ADR 031), `use_cases_approve` (ADR 032), `use_cases_render` (ADR 033), and `use_cases_docs` (ADR 030). A tool's name says what it acts on, so `validate` and `verify` cannot be mistaken for each other; the commands keep their short names. Not `init` or `hooks` (a person sets up a repository), not `prune` (deleting evidence is a person's decision, chapter 12 §30), and not `record --interactive` (it needs a terminal).
- **Each tool call is the command itself** with `--json`: the same document, as text and as structured content. The tool's output schema is the command's published schema, made self-contained.
- A refusal is a tool error carrying the error document as text. A blocked gate or a verify run with run errors is a normal result that says so.
- A verdict an agent records is recorded exactly as a person's; the agent layer adds no rules and skips none.

## Consequences

- Good: agents and scripts read the same documents, checked by the same schemas; there is one set of rules.
- Good: the core is unchanged: the agent layer sits entirely on top of the core and the command line.
- Cost: nothing distinguishes a verdict an agent recorded from a person's. Recording who recorded a verdict would be a core change (an optional stored field), left for a later decision.
- Cost: each tool call starts the command afresh, which is simple and isolated but slower than an in-process call.

## Considered Options

- **Tools with their own logic** (summaries, combined steps): friendlier to agents, but a second set of behaviour to keep in line with the command line.
- **Every command, including `init`, `hooks` and `prune`:** complete, but lets an agent set up or change a repository's configuration, or delete evidence, unasked.
- **No MCP server; agents run the command line:** works today, but agents discover and call typed tools far more reliably.

## Confirmation

- `test_mcp.py` drives a real server over stdio: exactly the thirteen tools, and none for `prune`; input and output schemas valid and self-contained; each tool's document equal to the command's; verify, the gate and record through tools; a verdict recorded by a tool counting like any other; a refusal as a tool error; bad arguments refused before anything runs; an unknown tool a protocol error.

## Related Links

- `docs/design/20-mcp-tools.md`
- ADR 022 (the command line), ADR 015 (how a contract grows)
