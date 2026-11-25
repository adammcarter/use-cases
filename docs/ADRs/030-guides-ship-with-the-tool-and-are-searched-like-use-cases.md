# ADR 030: Guides ship with the tool, one short page per task, searched like use cases

## Status

Accepted - 2026-09-30

## Context

Agents need to learn how to use Use Cases, and its quirks, without a person explaining. The owner's notes ask for built-in docs and a tool that searches them by keyword. The design chapters are the design, written for designing Use Cases rather than using it. The owner chose short guides that ship with the tool.

## Decision

- **Guides ship with the tool**, one short Markdown page per task: `getting-started`, `writing-use-cases`, `finding`, `linking`, `verifying`, `reading-status`, `ci-and-hooks`, `quirks`. They describe the installed version, so they always match it.
- **`use-cases docs`** lists them; `docs <guide>` shows one; `docs <words>` searches them. **`use_cases_docs`** is the same for agents. It needs no workspace.
- **One result is one section** of a guide, matched and ranked exactly as `search` ranks use cases, and paged the same way with a `--next` token. A guide's exact name shows the guide.
- **The guides are held true:** every command and flag a guide names must exist, and a test checks it.

## Consequences

- Good: an agent asks the version it is talking to how to use it, and gets a short section, not a chapter.
- Good: one ranking, one paging model and one token shape for search and docs.
- Cost: the guides are a second body of text to keep in line with the chapters; the command and flag check catches names, not wrong advice.

## Considered Options

- **Search the design chapters:** always complete, but long and written for the design, not for use.
- **MCP resources instead of a tool:** the protocol's own way to offer documents, but hosts handle it unevenly and people at a terminal get nothing. The same pages can be offered as resources later.

## Confirmation

- `UseCases/Acceptance/test_docs.py`: the list in order, needing no workspace; sections found with typos, phrases and exclusions; pages covering every match once; `--next` passed alone.
- `BundledGuideLoaderTests`: each bundled guide is the published one byte for byte, none is published that the build does not bundle, and they come in the order of the design.
- `DocsCommandTests`: a guide's name shows the guide as written.
- `GuidesHeldTrueTests`, through `GuideCheck`: every command, flag and file a bundled guide names exists; `GuideCheckTests`: a command or a flag that does not exist is a problem.
- `test_mcp.py`: the tool's document equal to the command's.

## Related Links

- `docs/design/16-cli-surface.md` §16
- `docs/design/20-mcp-tools.md`
- `docs/schemas/output/cli-docs.schema.json`
- ADR 029 (search), ADR 027 (agents get the commands as tools)
