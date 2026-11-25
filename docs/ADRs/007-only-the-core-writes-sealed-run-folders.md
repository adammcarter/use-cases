# ADR 007: Only the core writes results, in sealed run folders

## Status

Accepted - 2026-09-25

Its report handling is superseded by [ADR 020](020-each-run-owns-its-reports.md): each run owns its reports, and nothing is deleted.

## Context

Evidence must be trustworthy and must describe known code. If transformers or commands wrote results directly, a buggy helper could file a verdict against the wrong code, and every helper would need to reimplement durability.

## Decision

Only the core writes `.use-cases/`. Each request is one run folder:

```text
.use-cases/run-order.json                   the allocation high-water mark
.use-cases/runs/<run-id>/
   run.json · start.json · results.jsonl · outputs/<validation-id>/{report, console.txt} · completion.json
```

- Run IDs are 32 hex digits and only go up. The newest matching sealed result wins.
- A run counts only once `completion.json` seals it. Sealed runs never change.
- Readers check a sealed run's digests before using it. A corrupt sealed run, or a stray folder, is a storage error, never silently skipped.
- The core copies each report into the run itself. A report path inside `.use-cases/` is INVALID.

## Consequences

- Good: helpers can't corrupt evidence.
- Good: every verdict keeps the exact report it came from.
- Good: interrupted runs never leak partial evidence.
- Good: runs don't share a global log or lock, so separate requests don't block each other.
- Cost: history grows one folder per request, so retention needs deliberate tooling.
- Cost: if the allocation high-water mark is lost, allocation stops until it is restored. That is deliberate: it never guesses.

## Considered Options

- **One workspace-wide results log:** simpler to read, but a shared append lock and no clean unit of evidence.
- **Transformers write results:** fewer copies, but no single place enforces the rules.

## Confirmation

- The report boundary is now confirmed by ADR 020's checks.
- `test_store.py` proves increasing IDs, a lost high-water mark refused rather than guessed, tampered runs reported as corrupt, and unsealed runs never counted.
- Every stored file in the acceptance suite is checked against its schema (ADR 011).

## Related Links

- `docs/design/12-results-storage.md`
