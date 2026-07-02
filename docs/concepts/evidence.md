# Concept: evidence vs proof

Two records sound similar but play very different roles. Getting the distinction
right is essential to understanding what "FRESH" does and does not mean.

| | **Evidence** | **Proof** |
|---|---|---|
| What it is | An **observation** — a record that something was seen or done | A **signed trust gate** — cryptographic certification |
| Authority | None on its own | ed25519 signature from trusted CI |
| Recorded by | `ucm evidence record` (agents, scripts, humans) | `ucm prove` in CI only |
| Makes a row FRESH? | **No** | **Yes** |
| Mutable? | Append-only; corrected via `evidence void` | Append-only, hash-chained, fail-closed |

## Evidence is observation

An **evidence event** captures *what happened* — "this test was run," "this demo
was performed," "this behaviour was observed." It is useful history and context,
but it carries **no trust authority**: an agent can record evidence, and recording
it does not certify anything.

```bash
# Append an observation (kind + result are free-form context):
ucm evidence record --repo . --use-case billing.core.apply_discount \
  --kind test_result --result pass --json

# Replay the append-only evidence history:
ucm evidence status --repo . --json

# Correct an earlier event without deleting history:
ucm evidence void --repo . --evidence <id> --expected-head <event> \
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

> Related but distinct: **showcase runs** (`ucm showcase …`) and **capsules**
> (`ucm capsule …`) record live demonstrations through their own ledger. Like
> evidence, a static observation or a demo run is a *prompt for* a real
> observation — it is not proof and does not by itself create a passing verdict.

See also: [proofs & ledger](./proofs-and-ledger.md) · [the matrix](./matrix.md) ·
[CLI reference](../cli.md).
