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
| "Approved by a human" on a showcase run | ✅ with a signed approval token | A trusted human sign-off is a **run-bound ed25519-signed approval token** (`approve-run` → `showcase approve --approval-token`), verified against a keyring the agent cannot swap. Without a token a user-required run stays `pending`; an agent can request but never mint one. See *Trusted user approval* below. |

In short: **the cryptography proves "this proof was signed by the key you chose to
trust."** Making that key mean *trusted CI rather than the local agent* is your
deployment's job — commit the public key, keep the private key CI-only, protect
the branch, and verify with `--base-ref` / a keyring. With that setup in place a
local actor cannot manufacture `FRESH`. Without it the proofs are still useful
integrity signals, but they are not a defence against an actor who controls the
shell. See [key management](./security/key-management.md) for the keyring, the
fail-closed table, and rotation/revocation.

## Trusted user approval

An agent can **request** approval but must not be able to **mint** it. Both halves
now hold. A trusted user sign-off is a **non-forgeable, run-bound ed25519-signed
approval token**, not a caller-asserted flag or a terminal prompt:

1. The plugin mints an `ApprovalRequest` bound to the exact run (run id, ledger
   head, evidence/CI digests, a short-lived single-use nonce). An agent/host can
   request it (e.g. the MCP `showcase_request_approval` tool) but cannot sign it.
2. The human signs it out-of-band in their own shell with a key held **outside**
   the workspace: `uc approve-run --request <req> --key-file <pem> --key-id <id>
   --out approval-token.json`.
3. `uc showcase approve --approval-token approval-token.json (--keyring <path> |
   --public-key <path>)` **verifies** the signature, the live-run binding, the
   nonce (single-use), the expiry, and the key's keyring-bound assurance tier —
   trust is **computed**, never asserted. A verified token is by definition a user
   sign-off, so it records `actorType: user`.

`showcase status` needs the **same** `--keyring` / `--public-key` to *display* a
recorded approval; without it, verification fails closed and the approval reads
`pending`. Interactive-CLI confirmation is still **not** a trust root (an agent
that drives the terminal can satisfy it). The full design, threat boundary, and a
worked end-to-end example are in
[ADR 0006](./adr/0006-trusted-user-approval-path.md) (accepted / implemented,
0.2.0). Still future work: an OS-backed / WebAuthn issuer and separate-device
approval.

Approval proof is bound to the generated plan hash and the finish event for the
run. Generated plans, capsules, and runbooks are prepared material until a run
records events against them.

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
