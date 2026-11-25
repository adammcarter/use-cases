# ADR 010: The core and its contract name no tool

## Status

Accepted - 2026-09-25

## Context

Use Cases must work for any repository: any language, framework, build system or test tool. The first working transformer targets Swift Testing, and that makes it easy for one tool's details to leak into the core specs and read as the design target.

## Decision

- The core chapters and the transformer contract (chapter 10) describe behaviour in tool-neutral terms.
- Everything tool-specific lives in the transformer catalogue, `docs/transformers/`, one file per transformer. That covers report flags, format quirks, what a tool can't see, and measured timings.
- Specific tools may appear in the core docs only as labelled examples.

## Consequences

- Good: adding support for a new tool is a new transformer and a catalogue entry. The core never changes.
- Good: the core docs stay readable for teams that never use Swift.
- Cost: tool knowledge is split across two places, and a reader following one tool end to end must read both.

## Considered Options

- **Ship language support inside the core:** convenient for the first tools, but every new tool changes the core.
- **Keep tool notes inside chapter 10:** one place to read, but the contract reads as Swift-shaped.

## Confirmation

- Nine realistic fixture repos (Python, C, Rust, Java, Kotlin, Go, JavaScript, Swift, and a Cucumber project) run through the same core and contract with no core change. Each one has its own transformer settings; only the report format differs (`fixtures/`, `UseCases/Acceptance/test_languages.py`).
- The core has no built-in list of tool folders. Each repo names its own build and dependency folders in `discovery.exclude`; `test_only_the_workspace_decides_which_folders_are_skipped` proves a marker inside `node_modules` is found until the workspace excludes it.
- One configurable JUnit-XML transformer serves five of those tools.
- The docs README maps where each kind of new feature belongs. A new test tool is a new transformer documented in `docs/transformers/`.

## Related Links

- `docs/transformers/README.md`
- `docs/design/10-bridge-settings-and-transformers.md`
