# Roadmap

Ideas not built yet. Nothing here is promised, and the order is not fixed.

## Keeping use cases coherent

- Find conflicting use cases mechanically. Today the agent searches for similar ones before adding a new one and the person settles any conflict; nothing scans a whole repo for them.
- Group use cases that look alike, so a conflict check works on small batches instead of everything at once.
- A pre-commit check that agents run to find incoherent or conflicting use cases, kept light enough to run on every commit.

## Linking use cases

- Use case references: keep the prose in a ticket (Jira, a GitHub issue) and commit its URL beside the code.
- Relationships between use cases, so related ones link to each other as a tree rather than only sharing a prefix.

## Agents and skills

- A dedicated agent for planning and managing use cases, tuned to the codebase's own edge cases.
- A dedicated agent for planning and presenting showcases.
- Scheduled showcases, so people can have agents perform them on a timer.
- A use-case file-structure skill: one file per smallest logical unit, grouped in folders, kept small and easy to find.

## Releases

- A Homebrew tap, so people can install with `brew install`.

## Outside the core

- Agent-powered review of each use case, as an external feature built on the core.
