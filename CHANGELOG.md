# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) (see docs/release.md). This is
**pre-1.0 (beta) software**: anything MAY change before `1.0.0`.

## 0.0.1 - 2026-07-03

Initial public beta. (The project was briefly published as `1.0.0`/`1.0.1`;
those tags overstated maturity for a pre-1.0 tool and were withdrawn. `0.0.1` is
the same code, honestly renumbered as beta.)

use-case-matrix gives a repo a living use-case matrix, binds each behaviour row
to the code that satisfies it, and marks a row **FRESH** only when trusted CI has
signed proof that the current code, binding, and verifier still match. Stale
claims surface instead of being silently trusted.

### Core

- **Trust engine** — `bind → verify → prove → scan`, backed by an append-only,
  hash-chained proof/evidence ledger and fail-closed ed25519 signature
  verification (`FRESH` / `SUSPECT` / `UNPROVEN` / `UNBOUND` / `INVALID`). A
  keyring supports per-key status + validity windows, rotation, and revocation.
- **Language-agnostic markers** (`//: @use-case: <id>` … `end`) with per-file
  comment-prefix inference; verifier presets for any language/CI (`js-vitest`,
  `python-pytest`, `go-test`, `generic`).
- **One contract, two transports** — every CLI `--json` envelope is mirrored by
  the MCP tools; trust-critical commands (`scan`/`verify`/`prove`) are CLI-only
  by design.
- **Hosts** — applicability + thin projections for Claude, Codex, Copilot, and
  OpenCode, plus session-start bootstrap injection.
- Ships as a single self-contained npm package (`ucm` + `ucm-mcp` binaries).

### Robustness (from clean-room dogfooding)

- Every CLI failure renders the standard `ok:false` JSON envelope — never a bare
  stack trace. Malformed config → `workspace_config.parse_error`; a malformed
  signing/public key → `signing_key.invalid` / `public_key.invalid`; a
  non-existent `--repo` → `workspace.not_found`; unknown flags → exit 2;
  `bind --register-existing` infers explicit mode.
- Validated across a 6-variant acceptance fleet (generic, JS/vitest,
  Python/pytest, MCP, host projections, adversarial/upgrade) against the packaged
  artifact.

### Distribution & security

- Published from a public repository via **npm Trusted Publishing (OIDC)** with
  build provenance; the shipped docs (security, reference, tutorials) resolve.
- Path-traversal / data-root containment; bounded, secret-redacted command
  output; `prove` is never exposed over MCP, and there is no generic shell over
  MCP.
