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

## Planned

### 0.2.0 — a trustworthy signal

- **Refactor-tolerant spans** — only genuine behavioural change trips the alarm;
  reformatting, moving code, and comment-only edits stop causing false
  "needs re-check" noise. (`roadmap.deferred.refactor_tolerant_spans`)
- **Change-impact mapping** — map a git diff to the behaviours it touches, so you
  see exactly what to re-verify. (`roadmap.deferred.git_diff_auto_mapping`)

### 0.3.0 — reach + release-grade trust

- **Beyond GitHub** — proven CI authority adapters for GitLab and CircleCI, not
  just GitHub Actions. (`roadmap.deferred.ci_authority_adapters`)
- **Human sign-off agents can't fake** — a cryptographically-enforced trusted
  approval path, so an AI driving the same CLI/MCP cannot self-approve.
  (`roadmap.deferred.trusted_host_confirmation_path`)

### 1.0.0 — polish + freeze

- **Human-readable trust output** — the signing/verify/scan commands gain a
  friendly view, not just machine JSON.
  (`roadmap.deferred.human_readable_trust_output`)
- **Locked contracts** — commands, outputs, and file formats are frozen at 1.0 so
  what you build on won't shift under you. (`roadmap.deferred.v1_contract_freeze`)

## Backlog (unscheduled)

Further ideas kept visible but not yet slotted into a release live in
[`use-cases/roadmap/deferred.yml`](use-cases/roadmap/deferred.yml): a signed audit
log, advanced monorepo component scoping, direct MCP user-approval writes, MCP host
projection/conformance tools, a multi-machine capsule runner, a public registry
publication channel, behavioural host evals, automated freshness hard gates, and a
destructive secret/legal purge path.
