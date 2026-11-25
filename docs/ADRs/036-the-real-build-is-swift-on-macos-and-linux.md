# ADR 036: The real build is Swift, on macOS and Linux for v1

## Status

Accepted - 2026-10-17

## Context

The design is locked: the chapters, schemas and ADRs are the contract. The real build is an implementation of that contract. The owner's notes ask for a complete rewrite in Swift: a core package, a CLI and an MCP package. Swift is first-class on macOS and Linux; on Windows it works, with rougher tooling.

## Decision

- **The real build is Swift:** a core package, a CLI built with Swift Argument Parser, and the MCP server.
- **v1 runs on macOS and Linux.** Windows is not in v1.
- The contract stays platform-neutral: the chapters keep their Windows rules (paths, launchers, `PATHEXT`), so a later version can add Windows without a design change.

## Consequences

- Good: one language for the core, the CLI and the MCP server, first-class where the owner and most agents and CI run.
- Cost: people on Windows wait for a later version.

## Considered Options

- **Python:** quick to write, but rejected: the owner asked for a complete rewrite in Swift.
- **Windows in v1:** wider reach, but its Swift tooling would slow v1 for few users.

## Related Links

- `docs/architecture.md`
- ADR 010 (the core names no tool)
