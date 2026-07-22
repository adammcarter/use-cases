# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org) (see docs/release.md). This is
**pre-1.0 (beta) software**: anything MAY change before `1.0.0`.

## 0.5.0 - 2026-07-22

Variant parametrization: declare the input shapes of one behaviour (`0/1/many`,
`empty vs null`, negative, boundary) as **variants of a single use-case row**,
prove them all with one `uc verify` invocation, and see exactly which shape is
failing in `uc scan` — instead of hand-copying N near-identical rows or hiding
every shape behind one aggregate verdict. Everything is additive: a matrix
without `variants` behaves byte-for-byte as 0.4.1 (pinned by a golden
semantic-hash test), and no existing command, field, or output shape changed.

### Added

- **`variants` on a use-case row** (`[{ key, title? }]`, keys `[a-z0-9_-]+` and
  unique per family). The family stays ONE row — one id, one code binding, one
  shared verifier; its variants are parameters, not extra rows, so the marker/
  slug grammar and the binding registry are untouched.
- **`{variant}` token in verifier commands** (inline and preset), substituted
  alongside `{slug}`. `uc verify` on a family spawns the shared command once per
  variant; each spawn's exit code is that variant's verdict; each variant gets
  its own ledger record (`<family>::<key>`, additive `variant_key` field, its
  own `row_hash`/`binding_set_hash`) and the 0.4.1 merge preserves them all
  across incremental runs. `--dry-run` previews the per-variant plan.
- **Per-variant status in `uc scan`**: a family is `VERIFIED_LOCAL` only when
  EVERY declared variant currently passes; otherwise the weakest variant status
  wins and `local_reason` names the failing variant(s). New additive
  `variant_local_status` breakdown array on family rows.
- **Honest refusals, never false green**: a family command with no `{variant}`
  token is a single surfaced `VARIANT_TOKEN_MISSING` spec error — every variant
  records `blocked`, nothing spawns, and `--dry-run` previews the same refusal
  instead of claiming it would run. `uc prove` refuses variant families with
  `VARIANT_FAMILY_UNSUPPORTED` (the signed tier has no variant model yet)
  instead of a `NO_PASSING_RESULT` remediation loop that `verify` could never
  satisfy.

### Compatibility

- Old matrices, ledgers, and workflows are untouched under 0.5.0 — no
  migration. Adopting `variants` in a repo sets a version floor: `uc < 0.5.0`
  rejects the field with a loud schema error (never a silent misread), so
  collaborators must upgrade before a matrix starts using variants.

## 0.4.3 - 2026-07-20

0.4.2 was prepared but never tagged, so it never reached npm — `latest` stayed
on 0.4.1 and no installer ever saw the skill-discoverability fix. 0.4.3 is that
release plus the two fixes that landed after it. Everything listed under 0.4.2
below ships here for the first time. No command, field, or output shape from
0.4.1 changes.

### Fixed

- **A nested workspace's markers are no longer charged to its parent.** A
  workspace containing another workspace counted the child's markers as its own,
  so the parent's scan reported coverage it did not have. Marker collection now
  stops at a nested workspace boundary.
- **The installer test suite no longer depends on a locally installed host.**
  The agent-hook installer tests assumed a `claude` binary was on PATH and
  failed on machines without one, making the suite unrunnable in a clean
  environment.

### Changed

- **Version-parity tests derive the version instead of hardcoding it.** The
  release-gate, smoke, and pack tests pinned `0.4.2` in string literals and in
  packed tarball filenames, so every version bump broke them and the break was
  only discovered mid-release. They now read the root `package.json` version via
  `tests/helpers/package-version.ts`.

## 0.4.2 - 2026-07-20 (never published)

The skills this package ships have never been loadable. A general agent asked to
run a live showcase built a throwaway script instead — exactly the failure
`showcase/SKILL.md` exists to prevent — because it had no way to reach that file.
This release makes the four skills reachable and stops the tooling from calling
that state healthy. No command, field, or output shape from 0.4.1 changes.

### Fixed

- **The shipped skills are now discoverable by an agent.** `.agents/skills`
  contains `use-cases`, `showcase`, `walkthrough`, and `migration`, but nothing
  told a host they were there, and the package was never installable as a plugin
  in the first place — so it reached Claude only through the SessionStart hook,
  which delivers bootstrap text and cannot load skills. The plugin manifest now
  declares the directory (hosts only auto-scan `skills/` at plugin root), a
  marketplace manifest ships so the package can be added at all, and a global
  install registers the plugin through the host's own
  `claude plugin marketplace add` / `install`. Verified on a real host:
  `claude plugin details` reports `Skills (4)`.
- **A reinstall no longer silently skips registration.** Hosts report an
  already-added marketplace as a non-zero failure, which would have aborted
  before the install step — leaving every upgrade after the first with
  unregistered skills.
- **`uc doctor skills` no longer passes on skills nobody can load.** It checked
  only that the `SKILL.md` files existed and parsed, and stayed green through the
  entire period the skills were unreachable. It now also fails when no host
  declares a directory containing them (`skills.host_not_declared`) or the
  package is not installable (`skills.host_not_installable`), and reports a
  `host_registration` summary. This is additive: `complete` can now be `false`
  for a checkout that is missing host registration.

### Notes

- Registration goes through the host CLI only. This package never writes
  `~/.claude/plugins/*.json` itself — that state belongs to the host, and other
  installers converge it through the same CLI, so a second writer would disagree
  with the host about what is installed. `docs/hosts.md` records the boundary.
- Registration failure warns; it never fails the package install.

## 0.4.1 - 2026-07-14

Field-feedback patch, from two agents who used `use-cases` hard on a real
codebase and wrote up where it hurt. Their through-line: *the tool's green lights
are green when they shouldn't be, and an agent under pressure only looks at the
green light.* Everything here is a bug fix or a purely additive field — no
command, field, or output shape that existed in 0.4.0 has changed or been
removed.

### Fixed

- **`uc verify --row X` no longer destroys every other row's evidence.** The
  results ledger (`--out`, which `scan` auto-discovers) was written with a
  *truncating* write containing only the rows that run had targeted — so
  verifying one row erased the rest from disk and silently dropped them to
  `UNVERIFIED_LOCAL`. This punished the incremental `--row` flow the docs
  recommend and made `--all` the only safe option. `verify` now merges: rows it
  did not target keep their prior record, rows it did verify are replaced, and
  the ledger is sorted by `row_id` so it is deterministic. Staleness is still
  decided by re-checking each retained record's hashes against the current code,
  so a stale result is demoted, never trusted. `uc recover --row` inherits the fix.
- **Validation errors say where they are.** `✗ enum.invalid_value: must be equal
  to one of the allowed values` named no file, no row, and no *field* — though
  the JSON pointer already held it. The message now leads with the field name
  (`value_tier: …`), the diagnostic resolves its `entity_id` to the offending row
  id, and the human renderer prints the file/pointer/row it had been discarding.

### Added

- **`acceptance_claim` on `uc scan`** — `{ proven, total, claimable, statement }`.
  `guard_ok` answers a narrower question than its name suggests ("is any policy
  blocking?") and is `true` on a matrix where *nothing is proven*; both field
  reports record an agent nearly claiming acceptance off it. `guard_ok` keeps its
  meaning — existing gates do not flip — and scan now states the conclusion
  outright instead: `⚠ acceptance: NOT_SUPPORTED — 0 of 88 behaviours verified —
  do NOT claim acceptance`. A row counts as proven if either tier vouches for it
  (signed `FRESH`, or a current `VERIFIED_LOCAL` run); an `UNBOUND` row never does.
- **The summary counts the local axis** — `verified_local`, `stale_local`,
  `unverified_local`. It carried only the *signed* axis, which is `UNPROVEN` by
  design on every local run, so a fully green keyless matrix still read
  `fresh: 0, unproven: N` and looked like a disaster.
- **`remediation` on integrity errors, and the human view now shows them at all.**
  Integrity errors were JSON-only, and described the wreckage but not the cure.
  `ROW_NOT_FOUND` (what a renamed row produces) now names renaming as the likely
  cause and gives the re-register command; `UNREGISTERED_BINDING` gives the
  `--register-existing` command; `LEDGER_INTEGRITY_ERROR` points at
  `uc validate-ledger`. An `UNBOUND` row's `required_action` was `null` in the
  core — the status most likely to need a next command — and now carries the bind
  command.
- **Scan detects a likely rename.** Renaming a bound row produced `REGISTRY_ROW_MISSING`
  + `UNREGISTERED_BINDING` — "both messages are true and useless." The tool could
  see both halves (a registered row that vanished, a near-identical unregistered
  marker that appeared) and made you work it out. It now pairs them and names the
  rename in both errors. Conservative: it suggests a rename only when exactly one
  candidate is plausible, and stays silent rather than guess wrong.
  **It also tells the truth about the cure.** The binding registry is append-only
  with no retract event, and `uc bind` validates the registry first — so it fails
  *closed* on this very error. The only sequence that actually works today is to
  delete the stale line from `.use-cases/bindings.jsonl` and then re-register, and
  that is what the remediation says. (A first-class `uc bind --rename` needs a new
  registry event type, which would break mixed-version teams — so it is 0.5.0 work,
  not a patch.)
- **`uc verify --dry-run`** — show which verifiers would run for the targeted rows,
  run nothing, write nothing. `bind` and `prove` both had one; `verify`, the
  expensive command, did not. An `acceptance` verifier is often a full build, and
  not being able to see the cost before paying it is a leading reason evidence is
  left to rot. A plan is never evidence: it spawns nothing and mints no record.
- **`uc bind` ends by telling you the row proves nothing yet** — a new `next_command`
  (`uc verify --row <id>`). Binding succeeds and *feels* like progress, so rows get
  bound and left `UNPROVEN` forever ("all 7 of my rows are in exactly that state
  right now").
- **`uc init` writes a `.gitignore`** covering `showcase-runs/` and
  `.use-cases/verification-results.jsonl`. Transient run output was left untracked
  and unignored, dirtying the adopter's tree and tripping their own clean-tree
  gates. Append-only and idempotent: an existing `.gitignore` is never rewritten
  or reordered, and an entry the adopter already wrote is left alone.

### Changed

- **`uc impact` leads with the union of span-hit and file-touched rows.** It
  counted span overlaps only, so it announced `0 behaviours impacted — nothing
  impacted` directly above a list of rows sitting on files the change had edited,
  and an agent that reads the headline and stops skipped re-verifying exactly the
  rows that needed it. Span overlap is a weak proxy for behavioural impact — you
  can gut a function's semantics from a helper below the bound span. Touched rows
  are now treated as impacted-until-proven-otherwise and carry the same runnable
  re-verify command. A false positive costs one re-verify; a false negative ships
  a regression under a green badge.

## 0.4.0 - 2026-07-08

### Added

- Global npm installs now register the trusted session-start bootstrap for
  Claude Code, Codex, Copilot CLI, and OpenCode.
- OpenCode activation now uses the native message-transform plugin path while
  preserving `session.started` compatibility.

## 0.3.0 - 2026-07-05

### Changed

- **Marker grammar is now spaceless.** A marker is `<prefix>: @use-case:<payload>`
  — the space after `@use-case:` is gone (`//: @use-case:checkout.apply_coupon`,
  `//: @use-case:end checkout.apply_coupon`). A single space is still tolerated on
  input for compatibility, but the canonical/emitted form is spaceless. Every
  in-repo marker was migrated.
- **Refactor-tolerant span hashing (canon `ucase-span-lines-v2`).** The span
  canonicalizer now ignores cosmetic reformatting before hashing: it strips the
  common leading-whitespace prefix (so shifting a whole block in/out an indent
  level no longer flags drift) and collapses blank-line runs (plus the existing
  trailing-whitespace strip). Relative indentation and real content edits still
  change the hash — including Python nesting, since only the *shared* indent is
  stripped. Combined with `@use-case:ignore` regions, cosmetic edits stop
  producing false drift. (Greenfield canon bump — no existing proofs to migrate.)

### Added

- **Explicit `begin` directive.** For authors who want explicit span boundaries:
  `//: @use-case:begin <slug>` … `//: @use-case:end <slug>`. An explicit `begin`
  requires an explicit `end` (it never gets an inferred end). The bare-slug start
  (`//: @use-case:<slug>`, implicit begin) remains the default and is unchanged.
- **Ignore regions in spans.** `//: @use-case:ignore:begin` … `//: @use-case:ignore:end`
  carve cosmetic lines (comments, debug logging) out of a span so editing them
  does not change the span hash. The ignore markers and everything between them
  are dropped before hashing. Regions must be balanced and may not nest — an
  unbalanced/nested region is a hard error, never a silent drop. This is the first
  use of the general boundary rule `@use-case:[<block-path>:]<begin|end>`.
- **`uc showcase request-approval`** — mint the unsigned `ucase-approval-request-v1`
  from the CLI (previously only reachable via the MCP `showcase_request_approval`
  tool). It cannot sign or approve; an operator still signs out-of-band with
  `approve-run`.
- **`uc showcase status` surfaces the approver** — the verified `actor_type` and
  `assurance_tier` of a run's approval (sourced from the signed token, not a
  caller-asserted string).
- **Package-manager-agnostic `uc init` scaffold** — detects the target workspace's
  lockfile (pnpm/yarn/npm/bun) and emits the matching vitest run command, or a
  neutral `npx` default, instead of hardcoding pnpm.

### Fixed

- **`uc recover` failure output** — a failed recover now shows the reason and the
  next step in human output (previously only in `--json`).

## 0.2.0 - 2026-07-04

Trustworthiness + reach: know what a change touches, and make human sign-off
something an agent genuinely cannot fake.

### Added

- **`uc impact` — change-impact map.** Given a git change (working tree, `--base
  <ref>`, or `--staged`), it lists which bound behaviours your diff touches via
  line-level overlap with each binding's span: `impacted` (a hunk overlaps the
  span — re-verify these), `touched` (file changed, span didn't), and
  `broken_bindings` (the marked file was deleted or renamed away). Purely
  advisory — it never changes a trust verdict and writes nothing.
- **Trusted human approval an agent cannot fake.** A use-case that requires human
  sign-off is now approved by a **signed, run-bound, single-use token**, not a
  terminal prompt. A human mints it out-of-band with `approve-run`, signing with
  an ed25519 key held outside the agent's reach; the plugin verifies it against
  the same protected keyring your CI proofs use, and independently re-checks the
  run binding, the single-use nonce, expiry, and the key's keyring-bound
  assurance tier. An agent driving the CLI/MCP can **request** approval but cannot
  **mint** it. The previously spoofable, caller-asserted trust flags are deleted —
  trust is computed only from the signature — closing a latent hole where
  `showcase approve --actor user` could self-approve.
- **Human-readable trust output.** `scan`, `verify`, and `impact` print a friendly
  at-a-glance summary (status glyphs, a headline count, and the next action for
  non-green rows) when you don't pass `--json`. `--json` output is byte-identical.

### Notes

- Refactor-tolerant spans (planned for 0.2.0) was **deferred**: doing it safely on
  a code fragment needs a per-language lexer, and the daily "cries wolf" case is
  already a quick `verify`/`recover` away. It stays in the backlog.

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
- **Language-agnostic markers** (`//: @use-case:<id>` … `end`) with per-file
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
