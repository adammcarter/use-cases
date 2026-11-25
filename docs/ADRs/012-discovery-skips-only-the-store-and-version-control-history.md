# ADR 012: Discovery skips only the store and version-control history by default

## Status

Accepted - 2026-09-25

## Context

The core scans the workspace for scopes, use case files and markers. It must work on any repository, in any language, and name no tool (ADR 010). But some folders are not the workspace at all. An ordinary git repository would become INVALID because a commit message mentioned an unclosed marker: `.git/COMMIT_EDITMSG` and `.git/logs/HEAD` hold that text verbatim. A hard-coded list of build folders (`node_modules`, `target`, `.build`, …) would name tools and hide real code from teams that keep sources in such folders.

## Decision

- The core always skips its own store and version-control history, at any depth: `**/.use-cases/**`, `**/.git/**` (a `.git` file too), `**/.hg/**`, `**/.svn/**`, `**/.bzr/**`, `**/.jj/**`. Folder patterns work as in `.gitignore` (ADR 018).
- Nothing else is skipped by default. Build, dependency and generated folders are skipped only when the workspace lists them in `discovery.exclude` in the root `use-cases.yml`.
- Exclusions apply to scope discovery, use case discovery and marker scanning. A links transformer may not link into an excluded folder.

## Consequences

- Good: an ordinary repository works with no configuration, whatever its commit messages say.
- Good: no build or test tool is named by the core; each repo states its own folders, which is what the fixtures do.
- Cost: the version-control list names five systems. It is a list of history stores, not tools the contract depends on, and is closed.
- Cost: a repo without exclusions scans its build output too. That is slower, and a copied source file with markers in a build folder can give duplicate links. The fix is one `discovery.exclude` line, which `init` can propose.

## Considered Options

- **No defaults beyond `.use-cases/`:** purest, but a normal git repository can become INVALID from a commit message (reproduced).
- **A built-in list of common build folders:** convenient, but it names tools, is never complete, and hides folders some teams keep code in.
- **Honour `.gitignore`:** gives a Git model to a core that has none (chapter 04).

## Confirmation

- `test_version_control_history_is_never_scanned` commits a message containing a marker and the workspace stays valid; it fails without the default.
- `test_only_the_workspace_decides_which_folders_are_skipped` shows a marker in `node_modules` is found until the workspace excludes it.
- `test_a_links_program_is_trusted_for_nothing` refuses a link into `.git/`.

## Related Links

- `docs/design/04-workspace-structure.md` (discovery exclusions)
- `docs/design/09-workspace-loading.md` §7, §20.3
- ADR 010
