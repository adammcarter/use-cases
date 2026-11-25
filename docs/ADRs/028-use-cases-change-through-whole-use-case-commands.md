# ADR 028: Use cases change through three whole-use-case commands, planned before written

## Status

Accepted - 2026-09-29

## Context

Agents, and scripts, need to add, change and remove use cases without writing YAML by hand. The YAML stays the truth and people keep editing it, so every change a command makes must look like a careful person's edit, and must never leave the workspace INVALID. The owner asked for a resource-shaped design (one thing, shown, saved and removed whole) without resource terms on the command line; for `--dry-run` on every command that changes files people own; for the command code to be composed from small shared capabilities; and for commands to enforce the recommended file structure rather than offer ways around it.

## Decision

- Three commands, in the core: `use-cases show <id>`, `use-cases save --file F|-` (create or replace one use case, whole) and `use-cases remove <id>`. `show --json` returns exactly what `save` accepts. The MCP server offers them as `use_cases_show`, `use_cases_save` and `use_cases_remove`.
- **One use case's lines change, nothing else.** Every other use case, comment and blank line in the file is kept byte for byte. Fields are written in the order people read them, in the chapters' style.
- **The recommended structure decides where a new use case goes** (chapter 04): the file that already holds its group, or else a new file at the path its prefix spells. There is no option to choose another file.
- **Nothing INVALID is ever written.** Every change is planned first, then the whole workspace is loaded as it would be after the change; a change that would leave it INVALID is refused with nothing written.
- **`remove` never deletes evidence.** A use case's past verdicts stay in the store; markers still naming it are warnings.
- **`--dry-run` on `save`, `remove`, `init` and `hooks`**: everything but the write, returning the same document with `dry_run: true`. Not on `verify` or `record`, which only add to the results store.
- **The command code is composed capabilities** (`docs/architecture.md`): each command is a composition of shared behaviours, and every command that changes files builds a plan that one shared writer checks and applies. `--dry-run` is "stop before applying", so a preview cannot differ from the real run.

## Consequences

- Good: an agent changes use cases through tools, never YAML, under exactly the rules a person's edit meets.
- Good: files stay laid out one way, however many tools write to them.
- Good: one writer holds the checking and writing rules for every command, so a new command that changes files gets them unchanged.
- Cost: `save` edits block-style YAML only; a file that writes its use cases as a one-line flow list is refused and has to be edited by hand.
- Cost: nothing detects a file changed by someone else between `show` and `save`: the later save wins. A version check is left for a later decision.

## Considered Options

- **Field-level commands** (set one field, add one scenario): smaller requests, but many more commands and options, and partial states between them.
- **A `--file` or `--new-file` option to choose where a use case goes:** flexible, but opens layouts the design does not recommend.
- **Rewriting the whole file on every change:** simpler, but loses comments and layout people wrote.
- **REST terms on the command line** (`put`, `delete`): familiar to some, but not the words people use.

## Confirmation

- `test_edit.py`: show then save is `unchanged`; editing one field changes one line; comments and other use cases kept; new use cases added to their group's file or created at the structured path, nested groups and child scopes included; every kind of invalid change refused with nothing written; remove deleting an emptied file, keeping verdicts, warning about markers; `--dry-run` writing nothing and returning the real run's document for `save`, `remove`, `init` and `hooks`; `--dry-run` refused on commands that have none.
- `test_mcp.py`: show, save and remove through a real server; a refused save writes nothing.

## Related Links

- `docs/design/16-cli-surface.md` §14, §17
- `docs/design/04-workspace-structure.md` (recommended file structure)
- `docs/design/20-mcp-tools.md`
- `docs/architecture.md`
- ADR 022 (the command line), ADR 027 (agents get the commands as tools)
