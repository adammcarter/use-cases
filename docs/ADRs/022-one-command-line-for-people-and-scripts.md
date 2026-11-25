# ADR 022: One command line, written for people, with a versioned JSON contract for scripts

## Status

Accepted - 2026-09-27

## Context

The command line puts Use Cases in front of people, CI, git hooks and agents through one `use-cases` command. Once scripts depend on it, changing a command name, an output shape or an exit code breaks them, so those parts have to be fixed now, as firmly as the store and the transformer contract.

People and scripts want different things. A person wants a short, calm list with the worst at the top and a nudge towards the next step. A script wants a shape that never changes and exit codes it can branch on.

The shape was agreed with the owner in design: `status` absorbs a separate `why` command; plain `use-cases` means `--help`; output is written for people first, with `--json` for scripts; one hint line suggests the next command; `record --interactive` asks for each value.

## Decision

- **Commands:** `validate`, `status [<use case or prefix>] [--group] [--state] [--gate [--strict]]`, `verify --start|--finish|--run|--abort`, `record`, `record --interactive`, `links`, and `init` (chapter 17). Plain `use-cases` is `--help`.
- **The workspace is found by walking up** from the current folder to the `use-cases.yml` that says `root: true`. A child scope is passed over; a nested root is its own workspace. `--workspace` names it directly.
- **Human output is not a contract.** It may change in any release.
- **`--json` is the contract.** Stdout holds exactly one document, for success or failure, carrying `output_version: 1` and `command`. A refusal carries `error: {kind, message}`, where `kind` is `usage`, `invalid`, `refused` or `storage`. Every shape is a published schema in `docs/schemas/output/`, and it grows only by optional fields (ADR 015's rule).
- **Exit codes:** 0 done; 1 done, but something needs you (the gate blocked, or a verify run sealed with run errors); 2 refused; 130 cancelled. A failed test is not an exit 1 for `verify`: the gate decides what blocks, in one place.
- **`links --json` shows lines, never bytes**, exactly as transformers receive links.
- **`record --interactive`** asks for each value only in a terminal. Anywhere else, missing values are a usage error that names them; nothing ever waits for input that cannot come.
- **Hints:** at most one line, last, only in human output, removed by `--quiet`.

## Consequences

- Good: scripts and agents rely on one documented shape per command, checked against every output in the acceptance suite.
- Good: a person gets the worst first and one next step, and never has to remember ids to record a manual check.
- Good: exit codes let CI tell "your code broke a use case" (1) from "your setup is broken" (2).
- Cost: two outputs per command to maintain, and human wording can drift from the JSON unless both are kept in view.
- Cost: `verify` exits 0 when tests fail, which surprises anyone expecting a test runner's convention; the CI recipe (chapter 19) must pair it with `status --gate`.

## Considered Options

- **JSON by default:** easiest for scripts, hardest for people, and the people are the ones who adopt it.
- **A separate `why` command:** the same information as `status <use case>`, under a second name.
- **Exit 1 from `verify` when a test fails:** matches test runners, but splits "what blocks" across two commands and two rule sets.
- **`record` prompts whenever values are missing:** friendly, but a script that forgets an argument would hang waiting for input.

## Confirmation

- `test_cli.py` checks every rule of chapter 16: workspace discovery, help, version, ordering and filters, the detail view, usage errors and their kind, refusals, one JSON document per command, hints and `--quiet`, and `record --interactive` through a real terminal.
- Every `--json` document the acceptance suite sees is checked against its schema (`UseCases/Acceptance/conftest.py`), and every `verify` call checks that exit 1 means run errors and only that.

## Related Links

- `docs/design/16-cli-surface.md`
- ADR 015 (how a contract grows), ADR 021 (`verify` and `validate`), ADR 023 (the gate)
