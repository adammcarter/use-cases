# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) (see docs/release.md). This is
**pre-1.0 (beta) software**: anything MAY change before `1.0.0`.

## 0.1.0 - 2026-07-03

The **keyless daily loop**: a green "still covered" signal you get in seconds
with no keys and no CI. Cryptographic proof becomes an opt-in upgrade for
release/audit, instead of a prerequisite for everyday use.

### Added

- **Keyless local freshness (`VERIFIED_LOCAL`).** Each row now carries a
  `local_status` alongside the signed `status`: a bound row whose verifier
  passed locally reports `VERIFIED_LOCAL` — the daily green light — with no
  keypair and no CI. `verify` then `scan` closes the loop (`verify` now writes
  its unsigned results to `<data-root>/.use-cases/verification-results.jsonl` by
  default, and `scan` auto-discovers them). A trusted signed proof (`FRESH`)
  always satisfies the local light too; `STALE_LOCAL` / `UNVERIFIED_LOCAL` flag
  drift or not-yet-verified rows. Fully additive — the signed `status` and its
  derivation are unchanged.
- **`scan --gate`.** Opt-in exit-code gating for CI: exits non-zero when a
  required row is below the bar (`FRESH` in release mode, else at least
  `VERIFIED_LOCAL`). Without `--gate`, `scan`'s exit code is unchanged.
  `scan --results <path>` overrides the ledger location.
- **`ucm keygen`.** Generates the ed25519 keypair for the opt-in signed tier
  (PKCS8/SPKI PEM); `--out <dir>` writes them (private key `0600`, never inside
  the repo), `--ci github` emits a paste-ready OIDC release-workflow snippet.
- **`ucm recover`.** Drives a drifted/unproven row back to green in one command:
  re-verifies to `VERIFIED_LOCAL`, or with `--signing-key-env`/`--public-key`
  re-proves to `FRESH`. It confirms the row actually reached the bar before
  reporting success — a failing verifier or an unverifiable proof surfaces as a
  non-zero error, never a fake green.
- **Agent enablement.** The shipped agent skill, MCP playbooks
  (`ucm/adopt-repo`, `ucm/bind-row`, `ucm/recover-suspect-row`), and session
  bootstrap are refocused on the keyless daily loop, plus a new `docs/agents.md`.
  A conformance test keeps the agent guidance from drifting out of sync with the
  commands.

### Changed

- **`verify` without `--out`** now writes the unsigned results ledger to the
  default `<data-root>/.use-cases/verification-results.jsonl` (previously it
  wrote nothing). Explicit `--out` still wins. This is what makes the bare
  `verify` → `scan` keyless loop work with zero flags.

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
