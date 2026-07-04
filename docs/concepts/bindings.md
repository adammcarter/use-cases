# Concept: bindings, markers & freshness states

A **binding** connects a matrix row to the exact code span that implements it. It
is the link that makes "is this claim still true?" a mechanical question: if the
bound code changes, the row's freshness changes.

## Markers: the in-code grammar

A binding starts as a **marker** — a comment in your source using a stable
grammar that is independent of language:

```
<comment-prefix>: @use-case:<slug>
… implementing code …
<comment-prefix>: @use-case:end <slug>
```

For example, in TypeScript (`//`) or Python (`#`):

```ts
//: @use-case:billing.core.apply_discount
export function applyDiscount(total: number, percent: number): number { … }
//: @use-case:end billing.core.apply_discount
```

- The marker grammar (`//: @use-case:<slug>` … `//: @use-case:end <slug>`) and
  the slug rules are a versioned contract (see
  [stability](../reference/stability.md)).
- A **swift-func** binding is a shortcut for Swift: a single marker placed before
  a function declaration; the tool infers the span of the function body.
- A binding slug is the row id, optionally with a `#<suffix>` so one row can bind
  several spans (`billing.core.apply_discount#fast-path`).

## The binding lifecycle

```
            uc bind                 edit code / test            uc prove (CI)
 author ───────────────▶ registered ──────────────▶ status ◀──────────────── proof
 marker                  (bindings.jsonl)            via scan                  events
```

1. **Place** the marker in source.
2. **Register** it with `uc bind` — this appends a `binding_registered` event to
   the append-only registry (`.use-cases/bindings.jsonl` by default). `bind`
   refuses to register unless the edited file scans clean, so the registry never
   records a broken marker.
3. **Observe** status any time with `uc scan`, which reconciles the registry
   against the current code and the proof ledger.
4. **Prove** in CI to reach FRESH (see [proofs](./proofs-and-ledger.md)).

`bind` flags: `--row`, `--file`, `--mode explicit|swift-func`,
`--start-line`/`--end-line` (explicit) or `--line` (swift-func), optional
`--suffix`, `--register-existing` (register a marker you already placed without
editing source), `--comment-prefix` (override the inferred prefix), and
`--dry-run`.

## The five freshness states

`uc scan` derives exactly one status per row. They are evaluated in this
priority order (the first that applies wins):

| State | Meaning | How to fix |
|---|---|---|
| **INVALID** | The markers/registry are internally broken — a malformed or duplicate marker, an unregistered current marker, or a marker pointing at an unknown row. Blocks even in feature mode. | Run `uc scan` to see the integrity errors; fix the marker/registry so the file scans clean. |
| **UNBOUND** | The row exists but has no registered binding at all. | `uc bind` the row to its implementing code. |
| **SUSPECT** (removed) | A previously registered binding is gone from the code. | Restore the span, or re-bind to its new home, then re-prove. |
| **UNPROVEN** | Bound to current code, but no signed proof exists yet. | Let CI `verify` + `prove` the row. |
| **FRESH** | A trusted, signed proof matches the current row hash, binding-set hash, span hashes, **and** verifier context. | Nothing — this is the goal. |
| **SUSPECT** (stale) | A proof exists but no longer matches: the code span, row content, policy, binding set, or [verifier context](./verifiers.md) drifted since it was signed. | Re-prove in CI. The scan output names the drift (e.g. `CODE_SPAN_CHANGED`, `VERIFICATION_CONTEXT_CHANGED`, `ROW_HASH_CHANGED`, `BINDING_REMOVED`). |

The key property: a row can only be **FRESH** while everything it was proved
against is unchanged. Touch the bound code, weaken the test, or edit the row, and
it drops to **SUSPECT** — the stale claim becomes visible instead of silently
trusted.

## Policy modes

`uc scan --policy-mode <mode>` controls what *blocks*:

- **feature** (default) — blocks only INVALID rows.
- **release** — also blocks any `required_for_release` row that is not FRESH (and,
  if configured, applies the [authority gate](../security/ci-hardening.md)).
- **custom** — defers to a configured predicate.

## Where bindings are scanned

`scan` walks the product tree but skips build-output directories (`dist`,
`build`, `out`, `coverage`, `.next`, `.turbo`, `.svelte-kit`) alongside `.git`,
`node_modules`, and `.use-cases`, so a marker copied into compiled output is not
mistaken for a second binding.

See also: [the matrix](./matrix.md) · [verifiers](./verifiers.md) ·
[proofs & ledger](./proofs-and-ledger.md) · [error codes](../reference/error-codes.md).
