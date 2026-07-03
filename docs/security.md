# Security And Trust

Generated plans, migration output, capsules, and host projections are prepared
material only. They are not proof.

## Threat model — what holds on its own, and what needs setup

The freshness guarantee is cryptographic, but it is only ever as strong as the
trust anchor you give it. This tool's whole point is to keep claims honest, so it
is precise about what it enforces *by itself* versus what depends on how you
deploy it. The adversary worth naming is an **autonomous agent with full shell
access to the workspace** — the same actor the tool exists to keep honest.

| Property | Enforced by the tool alone | Also requires |
|---|---|---|
| A `FRESH` row carries a valid signature over the current row / binding-set / verifier hashes — any drift flips it to `SUSPECT` | ✅ `scan` fails closed on drift, bad/unknown/revoked/out-of-window signatures | — |
| That signature came from **trusted CI**, not a local actor | ❌ not on its own | The verifier must check against a **public key (or keyring) committed to the repo that the agent cannot swap**, *and* the private signing key must live **only** in a CI secret. Given a key it supplies or can generate, an actor with shell access can `prove` its own proof and `scan` it `FRESH`. |
| The proof ledger has not been rewritten | ❌ not on its own — a local rewrite re-chains the hashes consistently | `validate-ledger --base-ref <ref>` against a **protected** branch the agent cannot force-push (branch protection on that ref). |
| A required row was proven **on a protected branch** | ❌ | The release-gate authority requirement + the `protected_ref` attestation — see [CI hardening](./security/ci-hardening.md). |
| "Approved by a human" on a showcase run | ❌ in v1 | The showcase approval ledger is **unsigned**; sign-off is **operationally** enforced (process / review), not cryptographically. See *Trusted user approval* below. |

In short: **the cryptography proves "this proof was signed by the key you chose to
trust."** Making that key mean *trusted CI rather than the local agent* is your
deployment's job — commit the public key, keep the private key CI-only, protect
the branch, and verify with `--base-ref` / a keyring. With that setup in place a
local actor cannot manufacture `FRESH`. Without it the proofs are still useful
integrity signals, but they are not a defence against an actor who controls the
shell. See [key management](./security/key-management.md) for the keyring, the
fail-closed table, and rotation/revocation.

## Trusted user approval

An agent can **request** approval but must not be able to **mint** it. In v1 only
the negative half of that is real: `showcase approve` records an
`untrusted_automation` authority, and the showcase run ledger is **not signed** —
so a user-required run stays `pending` until approved out of band, and approval is
enforced **operationally** (your review process), not cryptographically. There is
no v1 code path that produces a cryptographically trusted user sign-off, and
interactive-CLI confirmation is **not** one (an agent that drives the terminal can
satisfy it). The signed-token approval path that closes this gap is specified in
[ADR 0006](./adr/0006-trusted-user-approval-path.md); it is planned, not shipped.
MCP tools can request approval but cannot fabricate it.

Approval proof, once it exists, is bound to the generated plan hash and the finish
event for the run. Generated plans, capsules, and runbooks are prepared material
until a run records events against them.

## Ledgers and history

Append-only ledgers preserve accidental or disputed history through correction
events. Normal commands do not physically delete evidence or showcase history.
Physical purge for secrets or legal requirements needs a separate destructive
workflow with explicit audit output. The append-only and hash-chain properties
are **verifiable**, not self-enforcing: validate them against a trusted prior
state (`validate-ledger --base-ref`) so a wholesale local rewrite is caught.

## Hosts and packages

Host profiles are expectation data. A host executable smoke result or projection
manifest can help diagnose setup, but verified host support requires recorded
evidence IDs.

Package checks inspect real tarballs or installed package roots. They reject
local/session state such as local agent cache and receipt directories, build
locks, packaged `node_modules/`, coverage output, local absolute paths, and
secret-looking values.
