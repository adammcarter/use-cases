# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) (see docs/release.md). This is
**pre-1.0 (beta) software**: anything MAY change before `1.0.0`.

## 0.0.3 - 2026-07-03

### Changed

- **Release automation.** A single tag push now produces the whole release via
  CI: `npm publish` with OIDC Trusted Publishing + provenance, the correct
  dist-tag, and — new in this release — the **GitHub Release**, auto-created by
  `softprops/action-gh-release` (no more manual `gh release create`). Pre-1.0
  `0.0.x` releases publish to the `latest` dist-tag (only true prereleases →
  `beta`), so `npm i use-case-matrix` always resolves the newest release.

## 0.0.2 - 2026-07-03

Patch fixes surfaced by continued dogfooding of the 0.0.1 beta.

### Fixed

- MCP `doctor_roots` now emits the `writable` field, matching the CLI — restoring
  the "same JSON contract on both transports" guarantee.
- The `js.vitest` verifier preset runs `npx --no-install vitest` instead of
  `pnpm`, so `verify` works on npm-only machines (no global pnpm required);
  pnpm users are unaffected.
- `doctor package` returns a non-zero exit code when its envelope is `ok:false`
  (previously it could report `ok:false` with exit 0).

### Added

- `ucm init --template js-vitest` now scaffolds a **runnable** example — a marked
  `src/example.ts` span plus a matching vitest test — so `verify` works out of
  the box, at parity with the python-pytest template.

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
