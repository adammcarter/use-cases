# ADR 0001: P0 Bootstrap Decisions

Date: 2026-06-24
Status: Accepted for P0

## Context

An external reasoning model reviewed the P0/P1 kickoff and flagged one blocker before scaffolding:
the installed-plugin launch model must be explicit before package manifests,
CLI entrypoints, and MCP startup tests are written.

The current repo starts from a reviewed design spec and the implementation plan.
P0 turns that into a runnable TypeScript workspace.

## Decisions

### Runtime And Package Manager

- Runtime target: Node.js `>=22`.
- Development machine baseline observed during P0: Node `v24.16.0`.
- Package manager: `pnpm@11.9.0` via Corepack.
- Root `package.json` must set `"packageManager": "pnpm@11.9.0"`.
- Commands in docs and tests may use `corepack pnpm` when global `pnpm` is not on `PATH`.

### Module Format

- All packages are ESM-only for v1.
- Package exports must point at built `dist/` files, not TypeScript source.
- No dual CommonJS output in P0.

### Version Ownership

- The root package owns the release version.
- P0 uses one authoritative version for:
  - root package
  - package versions
  - CLI `--version --json`
  - MCP `serverInfo.version`
  - plugin manifest versions
- Independent package versioning is deferred until there is a real release need.

### Package Names And Executables

- Root package name: `use-case-matrix`.
- Core package name: `@adammcarter/use-cases-core`.
- CLI package name: `@adammcarter/use-cases-cli`.
- MCP package name: `@adammcarter/use-cases-mcp`.
- CLI executable: `uc`.
- MCP executable: `uc-mcp`.

### Installed-Plugin Launch Model

The v1 installed plugin ships built JavaScript and package metadata. It must not
depend on workspace symlinks, repo-relative TypeScript paths, `tsx`, or the root
development `node_modules`.

P0 proves this with three gates:

```text
workspace smoke
  source checkout can import built package entrypoints and run CLI/MCP

packed consumer
  package tarballs install into a clean temp project and runtime imports,
  type declarations, CLI bin, and MCP bin work from the installed packages

staged plugin
  only distributable files are copied to a clean staged plugin root and every
  manifest command/path resolves inside that staged root
```

During development, plugin manifests may point at source-repo built outputs.
Before release, staged-plugin tests must prove the same launch contract using
only distributable files.

### Schema Ownership

- JSON Schemas under `schemas/v1/` are canonical persisted contracts.
- TypeScript types are derived from or checked against schemas.
- `core` owns schema loading and exports schema metadata through public
  package exports.
- Hand-maintaining unrelated TypeScript interfaces and JSON Schemas for the
  same persisted object is not allowed.

### CLI JSON Contract

- CLI JSON output uses one envelope shape from P0 onward.
- `--version --json` must be implemented by our command handler, not by an
  argument-parser short-circuit that bypasses JSON formatting.
- Text output can be friendly, but JSON is the normative automation contract.

### MCP Startup Contract

- The MCP server starts over stdio.
- P0 supports `initialize`, `notifications/initialized`, and `tools/list`.
- P0 may advertise no domain tools yet.
- Stdout must contain MCP protocol messages only.
- Human-readable diagnostics go to stderr.

## Consequences

- P0 has more packaging tests than a normal scaffold, but it prevents a common
  plugin failure: a source checkout works while the installed plugin cannot
  start.
- Host-specific details stay adapters. Claude, Codex, Copilot, and OpenCode
  projections cannot assume a shared launch format until conformance proves it.
- P1 can build schemas on a stable ownership model instead of duplicating types.
