# Concept: proofs & the ledger

A **proof** is the signed assertion that makes a row FRESH. Proofs live in an
append-only, tamper-evident **ledger**, and they can only be minted by **trusted
CI**. This is the heart of the trust model: a claim is FRESH only when there is a
cryptographically verifiable, current proof behind it.

## Proof events

A proof is an ed25519-**signed** event (`schema: ucase-proof-event-v1`). The
signature covers everything that defines what was proved, so none of it can be
altered after the fact without breaking verification:

- the **row hash**, **verification-policy hash**, and **approval-policy hash** —
  so editing the row or its policies invalidates the proof;
- the **binding-set hash** and each binding's **span sha256** — so changing the
  bound code invalidates it (see [bindings](./bindings.md));
- the **verification context hash** — so weakening the verifier or its inputs
  invalidates it (see [verifiers](./verifiers.md));
- a CI-neutral **`authority`** block recording who/where minted it (see
  [CI hardening](../security/ci-hardening.md)).

`scan` declares a row FRESH only when a trusted, passing proof matches **all** of
those current values. Any drift → SUSPECT.

## CI is the authority

The private signing key lives **only in trusted CI** — passed to `prove` via
`--signing-key-env <ENV>` from a secret, never written to the repo, never on a
developer machine. Minting is split so that signing is isolated from running test
code:

1. **`verify`** runs each row's resolved verifier and writes an **unsigned**
   results ledger (`--out`). It holds no key — safe to run on untrusted PRs.
2. **`prove`** **consumes** those unsigned results, **recomputes every hash
   itself**, and signs. It runs *no* scripts, so it is the only place the signing
   key is in scope, and an agent cannot feed it a forged "pass."

Because `prove` re-derives the hashes rather than trusting the input, a passing
proof cannot be forged from a forged "pass." But freshness is only ever as
trustworthy as **the key the verifier trusts**: `scan` proves "this proof was
signed by the key you chose to trust," not "by CI." So **local users cannot
manufacture FRESH _only when_** the public key (or keyring) is **committed to the
repo where the agent cannot swap it**, and the private signing key lives **only**
in a CI secret. Hand `scan` a `--public-key` the agent supplies — or let it
generate its own keypair — and an actor with shell access can sign and verify its
own `FRESH`. See the [threat model](../security.md#threat-model--what-holds-on-its-own-and-what-needs-setup)
for the full boundary. The
[GitHub Actions reference workflow](../../.github/workflows/use-cases.yml) wires
the trusted setup up: `verify` (keyless) → `prove` (signs on the release branch
with the CI-only key) → persist the ledger back to the repo.

## The tamper-evident ledger

Proof events are appended to the ledger (`.use-cases/proofs.jsonl` by default).
It is:

- **Append-only** — events are never edited or deleted; corrections are new
  events.
- **A hash chain** — entries are linked so a retroactive edit is detectable **when
  the ledger is validated against a trusted prior state**. Run
  `validate-ledger --base-ref <protected-ref>` so the chain is diffed against a
  branch the agent cannot force-push; without that anchor a local actor can rewrite
  the whole file and re-chain it consistently, so "tamper-evident" means *evident
  to a checker that holds an external reference point*, not self-enforcing.
- **Fail-closed** — verification only ever *adds* trust. An entry whose signature
  cannot be verified (unknown key, revoked key, bad signature, out-of-window key)
  is an integrity failure, never a silent pass.

`ucp validate-ledger` checks this discipline — append-only structure (against
`--base-ref`), schema conformance, signatures, and internal hash consistency —
and is run as a blocking CI gate.

## The keyring: rotation & revocation

There are two ways to tell verifying commands which public key(s) to trust:

| Flag | Trust model |
|---|---|
| `--public-key <file.pem>` | A single key, trusted unconditionally — only as safe as the file the agent is pointed at; commit it where the agent cannot swap it. |
| `--keyring <file.json>` | A registry of keys, each with a `status` (`active`/`revoked`) and a validity window. Opt-in; wins over `--public-key` when both are present. |

Both are accepted by `scan`, `verify`, `prove`, and `validate-ledger`. A key
resolves **only when** it exists, is `active`, and the proof's `created_at` falls
inside its validity window — otherwise the proof cannot verify and the row cannot
be FRESH.

- **Rotation**: add the new key (`active`), keep the old one active, **re-prove**
  the rows under the new key, then revoke the old key last. Order matters so no
  row flickers out of FRESH.
- **Revocation**: flip a leaked key's `status` to `revoked`. Every proof signed
  by it immediately stops verifying (fail-closed); re-prove the affected rows
  under a current key.

Full procedures, the keyring schema, and the fail-closed guarantee table are in
[key management](../security/key-management.md).

See also: [bindings & freshness](./bindings.md) · [verifiers](./verifiers.md) ·
[evidence vs proof](./evidence.md) · [stability](../reference/stability.md).
