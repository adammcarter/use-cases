# ADR 0004: P3 Evidence Ledger Contracts

## Status

Accepted.

## Context

P3 records observed proof as append-only JSONL and derives current evidence
state mechanically. Evidence must not become approval, verification-policy
satisfaction, or final sign-off.

An external reasoning model reviewed P3 before implementation and identified fail-open risks in loose
replay ordering, damaged-line handling, and idempotency scope.

## Decision

Evidence replay uses aggregate `sequence` as the sole order authority.
`recorded_at` is audit/display metadata, and `event_id` is identity only. A
duplicate or missing aggregate sequence invalidates that aggregate.

Replay continues after damaged ledger input to recover inspectable state, but
damage is not hidden:

```text
torn final line
  excluded from replay
  complete=false

unparseable complete line
  unknown_scope_damage=true
  complete=false

invalid aggregate history
  affected aggregate status=invalid
  complete=false
```

Normal append operations use a data-root-wide evidence append lock:

```text
evidence/.locks/append.lock
```

That lock covers replay, idempotency lookup, event generation, sequence
allocation, append, file fsync, and result construction. P3 reports the actual
durability class it achieved.

Idempotency scope is:

```text
data_root + operation intent + idempotency_key
```

The persisted `intent_digest` excludes generated fields such as `event_id`,
`sequence`, `recorded_at`, aggregate ID, and storage path. A retry with the same
key and same digest returns the original event and appends nothing. A retry with
the same key and a different digest fails closed.

Evidence targets stable use-case IDs and captures the P2 semantic hash at the
time of evidence recording. Matrix linkage is a separate operation from replay:

```text
replay evidence
  independent of current YAML/files

link evidence to matrix
  resolves IDs/scenarios through P2
  compares semantic hash freshness input
```

Assurance is represented as deterministic facets and a convenience class. P3
does not emit approval, user sign-off, verification-satisfied, final-pass, or
policy-satisfied state.

## Consequences

P4 can wrap evidence append/status as stable CLI JSON without inventing replay
semantics.

P9 can expose MCP tools safely because evidence recording cannot impersonate
user approval.

Later showcase and verification layers can combine P2 intended behavior and P3
evidence history without changing the append-only ledger contract.
