# ADR 009: Helpers are configured in one root file and run as separate programs

## Status

Accepted - 2026-09-25

## Context

Helpers need configuration: which commands to run, where they run, what the report is called, and which transformer reads it. That configuration must stay out of use case files (ADR 000). Transformers must work in any language, and repositories range from one package to many projects in several languages.

## Decision

- Helpers are configured in one optional file at the workspace root, `use-cases-bridge.yml`. It is root-only in v1.
- Each validation entry has an `id`, an optional `report` name (inside the run's own reports folder, ADR 020), an optional `run` command, an optional `working_dir`, and a `transformer`. `{report}` is the only placeholder and is always an absolute path; a near miss of it, such as `{Report}` or `{reprot}`, is refused by name as a mistyped placeholder, and every other brace, a bare word in braces included, is plain text.
- `working_dir` is where the command runs and where relative paths in its report start. It must be an existing folder inside the project, never `.use-cases/`.
- A report is a file or a folder, because real tools need both. Maven and Gradle write one JUnit file per test class, and a Swift run needs its event stream plus the console to cover XCTest.
- Transformers are separate executable programs, launched directly as `<program> <job> <request.json> <response.json>`. The core never picks an interpreter. Both files are JSON carrying `"contract": 1`.
- The core trusts a transformer for nothing: every links-job link is checked before use, every results-job key must be one it sent, and a transformer that hangs is stopped after 120 s.
- Bundled transformers follow exactly the same contract.

## Consequences

- Good: use case files never change when tooling changes.
- Good: anyone can write a transformer in any language and test it with fixture JSON files. The acceptance tests run project transformers written in Python and shell.
- Good: a monorepo's services each run in their own folder, with no `cd` wrappers.
- Good: a missing file means no helpers, and the core still works.
- Cost: a monorepo with several packages lists all its validations in one root file.
- Cost: launching a process per transformer call adds a little overhead. At 5,000 use cases it is well under the test tool's own time.

## Considered Options

- **Settings inside `use-cases.yml`:** one file fewer, but it mixes helper configuration into the core's own configuration.
- **One bridge file per nested scope:** closer to each package, but adds inheritance rules. Deferred beyond v1; `working_dir` covers the need that was measured.
- **Commands always run at the root:** simpler, but every monorepo validation needed `sh -c 'cd <service> && …'` (measured in the monorepo fixture).
- **The core runs transformers through an interpreter it chooses:** ties the contract to one language runtime.
- **In-process plugins, or a stdin/stdout protocol:** faster calls, but tied to one runtime, or harder to debug and replay.

## Confirmation

- `bridge.schema.json` and the four transformer contract schemas are checked by `validate.py`, including chapter 10's published examples.
- In the acceptance suite, every request the core sends and every response a transformer returns is checked against those schemas (ADR 011).
- `test_helpers.py` proves programs in any language, `working_dir`, the refusals of bad links and bad folders, and the transformer time limit. `test_monorepo.py` runs three services in their own folders.

## Related Links

- `docs/design/10-bridge-settings-and-transformers.md`
- `docs/design/14-run-commands.md`
- `docs/schemas/authored/bridge.schema.json`
