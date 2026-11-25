# ADR 017: Authored files are read one way, and the root is declared

## Status

Accepted - 2026-09-25

## Context

Users write use case files once and must never need to change them because an implementation reads them differently. An audit found several ways the same file could mean different things:

- **YAML versions disagree.** YAML 1.1 reads `on`, `No`, `1:30` and `2024-01-01` as a boolean, a boolean, a number and a date; YAML 1.2 reads them as text, and reads `1e3` and `0o17` as numbers where 1.1 doesn't. One file came out READY in one implementation, DRAFT in another, and crashed a third.
- **Duplicate keys were silently resolved**, and a value of the wrong type made a use case DRAFT instead of INVALID.
- **Ids depended on where the core was pointed.** Nested scopes compose prefixes, so pointing a tool at a child scope's folder produced different ids, and every marker in the code stopped matching.
- **Files could be orphaned** by a scope placed inside another scope's definitions folder.
- **Duplicate scenario or route ids** in one use case let evidence leak between routes.

## Decision

- Values are typed by YAML 1.2's core schema. A plain scalar, key or value, that YAML 1.1 would type differently is INVALID and must be quoted. Duplicate keys are INVALID.
- In use case files and use case input, unquoted text followed by a comment on its line is INVALID: YAML would silently cut the text at ` #`. Quoted text, and comments on their own line, are fine.
- Every authored file is checked against its published schema as it loads. A wrong type is INVALID, never DRAFT.
- The root `use-cases.yml` says `root: true`. Pointing the core at a folder whose `use-cases.yml` doesn't say it is refused. A `root: true` below the root marks a separate workspace, such as a vendored package or a submodule, which the parent never enters.
- A scope may not sit inside another scope's `use_cases_dir`, and a `use_cases_dir` may not contain its own scope's `use-cases.yml`. Every YAML file inside it must be a definition.
- Scenario ids and route ids are unique within a use case.
- An `include` in a group that selects nothing is INVALID, rather than meaning "every use case".

## Consequences

- Good: an accepted file reads the same in every YAML library, every implementation and every folder a tool starts in.
- Good: vendoring a package that has its own use cases leaves both workspaces intact.
- Cost: authors quote a few words YAML would otherwise mistype, and put comments in use case files on their own lines. The error names the value and says what to do.
- Cost: one more line, `root: true`, in every workspace root. `init` writes it.

## Considered Options

- **Pin YAML 1.2 only:** correct, but files would still be misread by the 1.1 tools teams already run (linters, CI parsers).
- **Find the root by searching upward:** no new field, but the result depends on the folder a tool starts in and what sits above it, which is the ambiguity this removes.
- **Allow a child scope inside a definitions folder, and flag orphans:** more freedom, but two rules to learn where one suffices.

## Confirmation

`test_authored.py`: each ambiguous scalar is refused unquoted and read exactly when quoted, duplicate keys and wrong types are INVALID, duplicate scenario and route ids are INVALID, a missing `root: true` and a child-scope start are refused, a vendored workspace stays separate, and misplaced scopes and definitions folders are refused. `test_groups.py` covers the empty include.

## Related Links

- `docs/design/02-use-case-schema.md`, `docs/design/03-use-case-groups.md`, `docs/design/04-workspace-structure.md`
- `docs/design/09-workspace-loading.md` §14
