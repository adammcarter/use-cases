# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) (see docs/release.md).

## 1.0.1 - 2026-07-03

Patch release hardening the CLI against a clean-room dogfood of 1.0.0.

### Fixed

- Every CLI failure now renders the standard `ok:false` JSON envelope instead of
  a bare Node stack trace. A malformed `use-case-matrix.yml`, a bad signing key,
  or any other thrown error previously produced empty stdout plus a stack trace,
  breaking any script or agent parsing `--json`.
- `prove` / `scan` report a clean `signing_key.invalid` / `public_key.invalid`
  diagnostic for a present-but-malformed PEM key instead of a raw OpenSSL crash.
- Unknown / typo'd flags are rejected with exit 2 rather than silently ignored
  (a mistyped `--end-line` no longer binds the wrong span).
- `matrix validate` (and every workspace command) surfaces `workspace.not_found`
  for a non-existent `--repo` instead of reporting `valid: true`.

### Changed

- The maintainer-only `doctor skills` / `doctor package` subcommands are hidden
  from generated help (still dispatchable for the release gate).

### Docs

- Ship the `docs/security/*`, `docs/reference/*`, `docs/tutorials/*`,
  getting-started, and docs-index pages in the npm package, so links from the
  shipped docs resolve.
- Document the trust commands (`bind` / `scan` / `verify` / `prove` /
  `validate-ledger`) in the CLI reference, and add a cross-platform (Node)
  ed25519 key-generation recipe (macOS LibreSSL cannot `genpkey ed25519`).

## 1.0.0 - 2026-06-30

First public release. Builds on rc.1 with a full identity completion, an
adoption-hardening pass driven by real foreign-agent usage, and session-start
bootstrap delivery.

### Added

- **Session-start bootstrap delivery** across all four host families: a polyglot
  `hooks/session-start` (Claude/Copilot/Codex via `hooks.json` + `hooks-codex.json`)
  and an OpenCode plugin (`.opencode/plugin/use-case-matrix.js`) inject the
  trusted `bootstrap/use-case-matrix.md` at session start (use case
  `hosts.profiles.bootstrap_autoinject`).
- `matrix upsert --use-case-file` (read a row from a file, not just inline JSON).
- Human-readable `ucm --help` / `ucm <command> --help` (text by default; `--json`
  for the envelope) with a complete flag catalog (bind span flags, the
  prove/verify/scan key flags, and the full showcase verb set).
- The code-marker grammar is documented (`docs/markers-adoption.md`, now shipped)
  and ADR 0006 specs the planned trusted user-approval path.

### Changed

- Completed the `presentation-skills` → `use-case-matrix` identity rename
  (envelopes, defaults, config, the self-matrix, source markers); CI mints FRESH
  proof for the plugin's own bound rows.
- The result envelope's `ok` is now `false` whenever an error-severity diagnostic
  is present; enum validation messages list the allowed values.

### Fixed

- `ucm bind` preserves a source file's executable bit when inserting a marker.
- Comment-prefix resolution recognises shebang (`#!`) scripts, so extensionless
  hooks can carry markers.
- The marker scanner skips `.claude/` (avoids duplicate-slug false positives from
  worktree copies); the evidence ledger tolerates foreign JSONL files instead of
  throwing; TEST-MATRIX migration accepts the British "Behaviour" header.
- Corrected stale `use-cases <cmd>` guidance to `ucm <cmd>` and fixed dead
  documentation links / `init` next-steps.

### Validated

- Adoption tested across a fleet of varied sandbox repos (greenfield Python/TS/Go/
  Swift/shell, a monorepo, docs-only, a legacy TEST-MATRIX migration, the live
  showcase lifecycle, cross-host activation) plus retroactive adoption on large
  real repositories. All findings triaged; the high-value gaps above were fixed.

## 1.0.0-rc.1 - 2026-06-29

Public v1 hardening — taking the internal trust engine to a public, adoptable
release. At a high level:

### Changed

- Renamed the project to **Use Cases Plugin**, published under the
  `@use-case-matrix/{core,cli,mcp}` scope with the `ucm` CLI (alias
  `use-case-matrix`) and `ucm-mcp` MCP server.

### Added

- Declared **public API + SemVer contract**: CLI command/flag names and `--json`
  envelopes, exit codes, MCP tool names/schemas, persisted file formats, and the
  documented `@use-case-matrix/core` exports are now versioned surfaces.
- **Tamper-evident, hash-chained ledger** — append-only proof/evidence ledger
  that detects edited, reordered, or truncated entries.
- **Keyring** with fail-closed key resolution: signing keys carry status and
  validity windows, with rotation and revocation support; unknown/revoked/
  out-of-window keys never verify.
- **CI-neutral authority** — an optional, signature-covered `authority` block on
  proofs (GitHub Actions reference path; GitLab CI / CircleCI / generic
  auto-detected) plus an opt-in release-gate authority requirement.
- **Verifier presets** — language/CI-neutral command verifiers, with `pnpm`/
  `vitest` as one preset rather than a built-in assumption.

### Security

- **Path-traversal hardening** — workspace-root containment with rejection of
  unsafe path / data-root boundary escapes.
- **Redaction** — bounded, secret-pattern-redacted command output captured as
  observations; `prove` is never exposed over MCP and there is no generic shell
  tool over MCP.

## 1.0.0

- Added sharded use-case matrix loading with damaged YAML recovery.
- Added append-only evidence and showcase ledgers.
- Added showcase and walkthrough planning, demo capsules, and live run commands.
- Added host profiles and thin projections for Claude, Codex, Copilot, and
  OpenCode.
- Added MCP tools that preserve CLI envelope semantics, including safe use-case
  mutation and capsule execution wrappers.
- Added TEST-MATRIX migration into draft use cases.
- Added end-to-end examples, dogfood release evidence, and sequential release
  packaging checks.
