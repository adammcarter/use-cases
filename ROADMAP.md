# Roadmap

`@adammcarter/use-cases` is **pre-1.0 (beta)** — this roadmap is a living plan,
and anything MAY change before `1.0.0`. Sequencing is a plan, not a promise;
items may move between releases or shift in scope.

The machine-tracked backlog lives in
[`use-cases/roadmap/deferred.yml`](use-cases/roadmap/deferred.yml) — the tool
dogfoods its own use-case matrix, so its own future is a set of `planned` rows.
This file is the human-readable shape of that plan.

## Shipped

### 0.1.0 — the keyless daily loop

The everyday "is this behaviour still covered?" check, made instant and setup-free.

- **Keyless local freshness (`VERIFIED_LOCAL`)** — a green signal from a plain
  local `verify`, with no keys and no CI. Cryptographic proof (`FRESH`) becomes an
  opt-in upgrade for release/audit instead of a prerequisite for daily use.
- **`scan --gate`** — a non-zero exit code for CI when a required behaviour is
  below the bar. Without the flag, exit codes are unchanged.
- **`keygen`** — one command (plus a paste-ready CI snippet) to turn on the signed
  tier, instead of hand-rolling keys.
- **`recover`** — drive a drifted or unproven behaviour back to green in one
  command; it confirms the row actually reached the bar and never fakes success.
- **Agent enablement** — the skill, MCP playbooks, and session bootstrap are
  centred on the keyless loop, with a currency test so the guidance can't drift
  from the commands.

### 0.2.0 — trustworthy signal + unfakeable sign-off

- **Change-impact map (`uc impact`)** — map a git diff to the behaviours it
  touches (line-level overlap with binding spans): impacted, touched, and
  broken-binding. Advisory — it changes no trust verdict.
- **Trusted human approval an agent cannot fake** — human sign-off is a signed,
  run-bound, single-use token minted out-of-band (`approve-run`) and verified
  against the protected keyring. An agent can *request* approval but cannot *mint*
  it; the spoofable caller-asserted trust flags are deleted, trust is computed
  only from the signature.
- **Human-readable trust output** — `scan` / `verify` / `impact` print a friendly
  at-a-glance summary (not just JSON) when you omit `--json`.

## Planned

### 0.3.0 — higher assurance + adopter reach

- **F1 refactor-tolerant spans with a per-language lexer** — stop flagging
  cosmetic edits (reformatting, comments) without missing real behavioural drift.
  Deferred from 0.2.0 after the multiline-string comment-strip safety hole made
  regex-only normalization too risky. (`roadmap.deferred.refactor_tolerant_spans`)
- **Higher-assurance approval tiers** — OS-auth, host-dialog, and WebAuthn /
  passkey approval paths flow into the same approval verifier, raising
  user-presence guarantees without splitting the trust model.
  (`roadmap.deferred.trusted_host_confirmation_path`)
- **`uc` approval-request helper** — mint the approval request from the CLI
  instead of requiring the MCP-only path.
- **Showcase approval status clarity** — `uc showcase status` surfaces the
  approver's `actor_type` and `assurance_tier`, so reviewers can see what kind
  of approval actually backed a run.
- **Package-manager-agnostic init scaffold** — `uc init --template js-vitest`
  detects the target workspace lockfile and prints pnpm, yarn, npm, bun, or
  neutral npx run commands instead of hardcoding pnpm.

### 1.0.0 — freeze

- **Locked contracts** — commands, JSON output, and file formats are frozen at 1.0
  so what you build on won't shift under you. (`roadmap.deferred.v1_contract_freeze`)

## Backlog (unscheduled)

Kept visible but demand-driven (see
[`use-cases/roadmap/deferred.yml`](use-cases/roadmap/deferred.yml)):
**GitLab / CircleCI authority adapters** (breadth — added when someone on those
platforms needs it), a signed audit log, advanced monorepo component scoping,
direct MCP user-approval writes, MCP host projection/conformance tools, a
multi-machine capsule runner, a public registry publication channel, behavioural
host evals, automated freshness hard gates, and a destructive secret/legal purge
path.
