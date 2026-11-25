# ADR 039: One release, three ways to install it

## Status

Accepted - 2026-10-17

## Context

The survey of sessions using today's plugin (`docs/research/plugin-survey.md`) found the CLI lived in a versioned plugin folder, so agents and git hooks could not find `use-cases` on their PATH. The real build (ADRs 036 to 038) runs on macOS and Linux. Three kinds of user need it: agents through the MCP tools, people and their git hooks at a terminal, and CI machines.

## Decision

- **One tagged release** builds the same binary for macOS (universal) and Linux (x86 and ARM).
- **Agents:** the plugin ships the binary for its platform, and its MCP configuration starts it directly: no install step.
- **People and git hooks:** the release download from GitHub, unpacked with `use-cases` linked onto the PATH.
- **CI:** the same release download, one pinned step in the CI recipes (chapter 19).
- **The release ships** one tarball per platform, a checksum for each, and the plugin. The plugin installs from the release's `use-cases-plugin.zip` through the marketplace in this repository.
- **Setup checks it:** step 0 (chapter 22) says when `use-cases` is not on the PATH and offers the release download; hooks fall back to the `use-cases` that added them (chapter 18).
- The plugin and the release downloads always come from the same tag, so they never disagree on the version.
- **Homebrew is dormant:** `release.yml` updates a Homebrew tap only when a `HOMEBREW_TAP_TOKEN` secret exists. None is set up, so nothing is published to a tap and nobody is told to `brew install`.

## Consequences

- Good: each kind of user gets `use-cases` from one build.
- Cost: two channels to publish on every release; a release workflow does both from the tag.

## Considered Options

- **The plugin only:** no extra install, but the command is not on the PATH, which is the survey's problem.
- **Build from source on first use:** always current, but slow, and needs a Swift toolchain on every machine.

## Related Links

- ADR 036, ADR 038, ADR 025 (hooks)
- `docs/architecture.md`
