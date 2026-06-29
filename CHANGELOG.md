# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) as declared in
[`docs/reference/stability.md`](docs/reference/stability.md).

## [Unreleased]

Public v1 hardening — taking the internal trust engine to a public, adoptable
release. At a high level:

### Changed

- Renamed the project to **Use Cases Plugin (UCM)**, published under the
  `@use-cases-plugin/{core,cli,mcp}` scope with the `ucp` CLI (alias
  `use-cases-plugin`) and `ucp-mcp` MCP server.

### Added

- Declared **public API + SemVer contract**: CLI command/flag names and `--json`
  envelopes, exit codes, MCP tool names/schemas, persisted file formats, and the
  documented `@use-cases-plugin/core` exports are now versioned surfaces.
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
