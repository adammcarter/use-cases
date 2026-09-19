# Concept: evidence vs proof

Two records sound similar but play very different roles. Getting the distinction
right is essential to understanding what "FRESH" does and does not mean.

| | **Evidence** | **Proof** |
|---|---|---|
| What it is | An **observation** — a record that something was seen or done | A **signed trust gate** — cryptographic certification |
| Authority | None on its own | ed25519 signature from trusted CI |
| Recorded by | `use-cases evidence record` (agents, scripts, humans) | `use-cases prove` in CI only |
| Makes a row FRESH? | **No** | **Yes** |
| Mutable? | Append-only; corrected via `evidence void` | Append-only, hash-chained, fail-closed |

## Evidence is observation

An **evidence event** captures *what happened* — "this test was run," "this demo
was performed," "this behaviour was observed." It is useful history and context,
but it carries **no trust authority**: an agent can record evidence, and recording
it does not certify anything.

```bash
# Append an observation (kind + result are free-form context):
use-cases evidence record --repo . --use-case billing.core.apply_discount \
  --kind test_result --result pass --json

# Replay the append-only evidence history:
use-cases evidence status --repo . --json

# Correct an earlier event without deleting history:
use-cases evidence void --repo . --evidence <id> --expected-head <event> \
  --reason "superseded" --json
```

Evidence events are append-only: a mistake is corrected by appending a `void`
event (with the expected ledger head, for safe concurrent correction), never by
editing or deleting the original.

## Proof is the trust gate

A **proof** is the only thing that turns a row FRESH. It is ed25519-signed by
trusted CI, recomputes its own hashes, and is verified fail-closed against a
trusted key. An agent cannot mint one, and it cannot be forged after signing. Full
mechanics are in [proofs & the ledger](./proofs-and-ledger.md).

## What the acceptance claim counts

`use-cases scan` reports an `acceptance_claim`, and it counts a row proven at exactly
three tiers — never on the strength of prose:

| Tier | What it means | How you get one |
|---|---|---|
| `signed_proof` | trusted CI signed that the current code still backs the row | `use-cases prove` in CI |
| `local_run` | `use-cases verify` **spawned this row's verifier here** and it passed | `use-cases verify` |
| `performed_run` | **`use-cases` drove a command against the product** and it passed | `use-cases evidence record --perform -- <cmd>` |

`by_evidence` breaks the count down by tier and `basis` says it in words, because
a bare "285 of 297 verified" cannot distinguish 285 demonstrations from 285 unit
filters. Each row is counted once, at its strongest tier.

### A local run must prove a run wrote it

The unsigned results ledger (`.use-cases/verification-results.jsonl`) is a plain
text file, and it is **transient per-machine output** — `use-cases init` gitignores it
for that reason. `scan` used to accept any line in it whose hashes matched the
current code, but those hashes are computable by anything that can read the repo,
so they never separated a run from a text edit.

Every record `use-cases verify` writes now carries a **run attestation**: an HMAC over
the record's own content, keyed by a secret at `~/.use-cases/run-key`
(override with `UC_RUN_KEY_FILE`) that is minted on first use and never lives in
the repo. A record without a valid one reads `UNATTESTED_LOCAL` and is never
counted as proven.

This is **not** the signing tier: no CI, no keyring, nothing to configure. It is
tamper-*evident*, not tamper-*proof* — anyone who can read the key file can forge
a record. That is the honest bound of a keyless local tier, and it is a long way
from "any line in a tracked file is proof".

Consequences worth knowing:

- **A results ledger committed by a teammate reads unattested on your machine.**
  Their run is not your evidence. Run `use-cases verify` and it is yours.
- **A ledger written before this version has no attestation**, so those rows read
  `UNATTESTED_LOCAL` after upgrading, and `scan --gate` in feature mode will
  fail on a required one. `use-cases verify --all` restores them in one command. Signed
  proofs are unaffected: a `FRESH` row stays `FRESH`.

### A spawned verifier is not a demonstration

Each verification result also carries `run_class`, derived from the verifier that
actually ran rather than from what the row declared:

- `suite` — the verifier expanded from a named test runner (`js.vitest`,
  `js.npm-test`, `python.pytest`, `go.test`). A unit suite, whatever the row calls it.
- `command` — an explicit script or `make.target`. It may genuinely drive the
  product, and the tool will not guess.

There is deliberately no `journey`: `verify` spawns a process, and a process is
not a demonstration. A demonstration is `evidence record --perform`, which
records the argv it drove. Where a row declares `evidence_kind: live_demo` over a
named test runner — an overclaim the tool can *prove* — the record carries
`evidence_kind_overclaimed` and `verify` names the row back to its author. The
declaration itself is left untouched; the ledger corrects nobody's YAML.

## Why the separation matters

If observation and certification were the same thing, any actor that can *write a
note* could *grant trust* — exactly the failure this system exists to prevent. So:

- **Evidence answers "what was observed?"** It is rich, low-friction, and
  agent-writable. Use it to track activity, capture demo results, and build
  history.
- **Proof answers "is this claim trustworthy right now?"** It is scarce,
  CI-only, and signed. Only proof gates FRESH and release.

A row with lots of recorded evidence but no current signed proof is still
**UNPROVEN** or **SUSPECT** — never FRESH. That is by design: evidence informs;
proof certifies.

> Related but distinct: **showcase runs** (`use-cases showcase …`) and **capsules**
> (`use-cases capsule …`) record live demonstrations through their own ledger. Like
> evidence, a static observation or a demo run is a *prompt for* a real
> observation — it is not proof and does not by itself create a passing verdict.

See also: [proofs & ledger](./proofs-and-ledger.md) · [the matrix](./matrix.md) ·
[CLI reference](../cli.md).
